import 'dart:math';
import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';
import 'new_search_rect.dart';
import 'route_transfer_objects.dart';
import 'side_point.dart';

/// Defines the side points update strategy during a position tick.
/// - `none`: Skips updates, calculating only the user's route progress.
/// - `active`: Fast-forwards and updates a limited amount of upcoming points,
/// starting from the one with state `next`. Counts only the points which
/// `state != past` after update.
/// - `all`: Forces a full O(N) update of all points, including passed ones.
enum SPUpdMode { none, active, all }

class RouteManager {
  /// `emaSmoothingFactor` - the smoothing factor (0.0 to 1.0) determining the
  /// weight of the new coordinate when calculating weighted vector of movement.
  /// * 1.0 = No smoothing (EMA instantly snaps to the new physical point).
  /// * 0.0 = Complete freeze (EMA never updates).
  /// A value of 0.5 provides a stable balance, effectively averaging the last few
  /// updates.
  RouteManager({
    required RMConfig config,
    double maxDeviationDeg = 45,
    double movementThreshold = 0.00001,
    int spUpdateBatchSize = 40,
    double finishThreshold = 5,
    double emaSmoothingFactor = 0.5,
    double jumpThreshold = 100.0,
  })  : _route = config.route,
        _distFromStart = config.distFromStart,
        _segmentsLen = config.segmentsLen,
        _srBuffer = config.srBuffer,
        _alignedSP = config.alignedSP,
        _wpIndices = config.wpIndices,
        _routeLen = config.routeLen,
        _maxDevCos = cos(maxDeviationDeg * deg2rad),
        _movementThreshold = movementThreshold,
        _spUpdateBatchSize = spUpdateBatchSize,
        _finishThreshold = finishThreshold,
        _emaAlpha = emaSmoothingFactor,
        _emaLat = config.emaLat,
        _emaLng = config.emaLng,
        _prevLat = config.prevLat,
        _prevLng = config.prevLng,
        _jumpThreshold = jumpThreshold,
        _activeWpPtr = config.wpIndices.length - 1;

  // naming:
  // RP - route point
  // SP - side point
  // WP - way point
  // SR - search rect

  final Float64List _route;
  final double _routeLen;
  double _coveredDist = 0;
  double _prevCoveredDist = 0;
  int _currRPInd = 0;
  int _nextRPInd = 1;
  int _prevRPInd = 0;
  int _currSegmInd = 0;
  int _prevSegmInd = 0;
  final double _finishThreshold;
  bool _isOnRoute = true;
  bool _isJump = false;
  final double _maxDevCos;
  final double _movementThreshold;
  final int _spUpdateBatchSize;

  /// {segment index in the route, search rect}
  final SearchRectBuffer _srBuffer;

  /// {index of aligned side point, side point}
  /// ``````
  /// In function works with a beginning of segment.
  final RawSidePointsBuffer _alignedSP;

  /// {segment index in the route, distance traveled form start}
  final Float64List _distFromStart;

  /// {segment index in the route, segment length}
  final Float64List _segmentsLen;

  // ===========================================================================
  // EMA (Exponential Moving Average) Direction Filter
  // ===========================================================================
  // GPS coordinates jitter, making point-to-point direction vectors unstable.
  // To fix this, we collapse the weighted differences between the current (C)
  // and past (P) positions into a single virtual point (EMA). Then we simply
  // update this EMA point on each GPS tick.
  //
  // Since the sum of all weights equals 1.0, the equation transforms like this:
  // Vx = w0(C - P0) + w1(C - P1) + w2(C - P2)
  // Vx = C - (w0*P0 + w1*P1 + w2*P2)  =>  Vx = C - EMA
  // ===========================================================================

  /// The virtual smoothed latitude and longitude, and it's smoothing factor.
  /// STRICTLY used to calculate a stable directional vector.
  final double _emaAlpha;
  double _emaLat;
  double _emaLng;

  /// The last received raw  physical latitude and longitude.
  double _prevLat;
  double _prevLng;

  /// exists to let position update at least 2 times (need to create vector)
  int _initTicks = 2;

  int _firstActiveSpInd = 0;

  final double _jumpThreshold;

  int _activeWpPtr;

  // замена для _wpList
  final Int64List _wpIndices;

  //-----------------------------Methods----------------------------------------

  /// Updates previous location using EMA (Exponential Moving Average) Filter
  void _updateListOfPreviousLocations(double currLat, double currLng) {
    final double diffLat = (_prevLat - currLat).abs();
    final double diffLng = (_prevLng - currLng).abs();

    if (diffLat < _movementThreshold && diffLng < _movementThreshold) return;

    // Обновляем виртуальную сглаженную точку
    _emaLat = currLat * _emaAlpha + _emaLat * (1.0 - _emaAlpha);
    _emaLng = currLng * _emaAlpha + _emaLng * (1.0 - _emaAlpha);

    // Сохраняем сырые координаты
    _prevLat = currLat;
    _prevLng = currLng;

    if (_initTicks > 0) _initTicks--;
  }

  void _updateIsJump(double currentDist, double previousDist) {
    if (_isJump == true || _initTicks > 0) return;
    _isJump = currentDist - previousDist > _jumpThreshold;
  }

  /// Логическое удаление точки. Сохраняет целостность _wpIndices.
  void deleteSidePoint(double pLat, double pLng) {
    for (int i = 0; i < _alignedSP.length; i++) {
      if ((_alignedSP.getLat(i) - pLat).abs() < _movementThreshold &&
          (_alignedSP.getLng(i) - pLng).abs() < _movementThreshold) {
        _alignedSP.setState(i, PointState.deleted);
        break;
      }
    }
  }

  bool isPointOnRoute({required LatLng point}) {
    // Распаковываем координаты один раз до входа в цикл
    final double pLat = point.latitude;
    final double pLng = point.longitude;

    // Количество сегментов берем из длины массива сегментов
    final int segmentsCount = _segmentsLen.length;

    for (int i = 0; i < segmentsCount; i++) {
      if (_srBuffer.isPointInRect(i, pLat, pLng)) return true;
    }
    return false;
  }

  /// returns a normalised weighted vector
  (double, double) _calcWeightedVector(double curLat, double curLng) {
    // Вектор от сглаженной истории к текущей точке
    final double vx = curLat - _emaLat;
    final double vy = curLng - _emaLng;

    final double inversedLen = 1 / sqrt(vx * vx + vy * vy);
    return (vx * inversedLen, vy * inversedLen);
  }

  bool _isSegmValid(
      int ind, double vLat, double vLng, double curLat, double curLng) {
    if (_initTicks > 0) return _srBuffer.isPointInRect(ind, curLat, curLng);

    final ({double lat, double lng}) segmVect =
        _srBuffer.getNormalisedSegmVect(ind);

    // cos(alpha) = (dotProd) / (v1.len * v2.len); in our case both len = 1
    final double dotProd = vLat * segmVect.lat + vLng * segmVect.lng;
    return _maxDevCos <= dotProd &&
        _srBuffer.isPointInRect(ind, curLat, curLng);
  }

  int _searchCycle(int start, int end, double vLat, double vLng, double curLat,
      double curLng) {
    int bestInd = -1;
    double minDistRadSq = double.infinity;
    bool foundValidGroup = false;

    for (int i = start; i < end; i++) {
      if (_isSegmValid(i, vLat, vLng, curLat, curLng)) {
        foundValidGroup = true;

        final int offset = i * 2;
        final double aLat = _route[offset];
        final double aLng = _route[offset + 1];
        final double bLat = _route[offset + 2];
        final double bLng = _route[offset + 3];

        // Проецируем координату на отрезок (t зажато в [0, 1])
        final proj = getProjectionRaw(curLat, curLng, aLat, aLng, bLat, bLng);

        // Квадрат дистанции от физической точки до проекции на линию
        final double distRadSq =
            getDistanceRadSq(curLat, curLng, proj.lat, proj.lng);

        // Конкуренция дистанций на перекрывающихся углах
        if (distRadSq < minDistRadSq) {
          minDistRadSq = distRadSq;
          bestInd = i;
        }
      } else if (foundValidGroup) {
        break;
      }
    }
    return bestInd;
  }

  int _findClosestSegmentIndex(double curLat, double curLng) {
    final int mapLen = _segmentsLen.length;

    double vLat = 0;
    double vLng = 0;

    if (_initTicks <= 0) {
      final (double, double) motionVect = _calcWeightedVector(curLat, curLng);
      vLat = motionVect.$1;
      vLng = motionVect.$2;
    }

    // 1. Ищем локально вперед от прошлого известного сегмента
    int closestSegmInd =
        _searchCycle(_prevSegmInd, mapLen, vLat, vLng, curLat, curLng);

    // 2. Если ушли с маршрута (или кольцо замкнулось), ищем с самого начала
    if (closestSegmInd == -1) {
      closestSegmInd =
          _searchCycle(0, _prevSegmInd, vLat, vLng, curLat, curLng);
    }

    _isOnRoute = closestSegmInd != -1;
    return closestSegmInd;
  }

  void updatePosition(LatLng currLoc, {SPUpdMode spMode = SPUpdMode.all}) {
    // 1. Core-логика позиционирования
    final double curLat = currLoc.latitude;
    final double curLng = currLoc.longitude;

    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int curLocInd = _findClosestSegmentIndex(curLat, curLng);

    _updateListOfPreviousLocations(curLat, curLng);

    if (!_isOnRoute) return;

    _currSegmInd = curLocInd;
    _prevSegmInd = curLocInd - 1;

    // Количество сегментов равно максимальному индексу точки (N точек = N-1 сегментов)
    final int maxInd = _segmentsLen.length;
    _currRPInd = curLocInd;
    _nextRPInd = min(curLocInd + 1, maxInd);
    _prevRPInd = max(0, curLocInd - 1);

    final int curOffset = curLocInd * 2;
    final double rpLat = _route[curOffset];
    final double rpLng = _route[curOffset + 1];

    final int nextOffset = _nextRPInd * 2;
    final double nextRpLat = _route[nextOffset];
    final double nextRpLng = _route[nextOffset + 1];

    // Вычисляем продольную проекцию пользователя на текущий сегмент
    final proj =
        getProjectionRaw(curLat, curLng, rpLat, rpLng, nextRpLat, nextRpLng);
    final double abSegLen = _segmentsLen[_currSegmInd];

    _prevCoveredDist = _coveredDist;
    _coveredDist = _distFromStart[_currSegmInd] + (proj.t * abSegLen);

    // 2. Логика обновления сайдпоинтов (DOD)
    if (spMode != SPUpdMode.none) {
      final bool updateAll = spMode == SPUpdMode.all;
      final int startInd = updateAll ? 0 : _firstActiveSpInd;

      bool firstNextFlag = true;
      int spUpdated = 0;

      for (int i = startInd; i < _alignedSP.length; i++) {
        final PointState currentState = _alignedSP.getState(i);

        if (currentState == PointState.deleted) {
          if (i == _firstActiveSpInd) _firstActiveSpInd++;
          continue;
        }

        // Пропускаем жестко отработанные точки ТОЛЬКО если это стандартный быстрый тик
        if (!updateAll && currentState == PointState.past) {
          if (i == _firstActiveSpInd) _firstActiveSpInd++;
          continue;
        }

        final PointState newState;
        if (_alignedSP.getAbsDist(i) <= _coveredDist) {
          newState = PointState.past;
        } else if (firstNextFlag) {
          newState = PointState.next;
          firstNextFlag = false;
        } else {
          newState = PointState.onWay;
        }

        if (currentState != newState) _alignedSP.setState(i, newState);

        // Указатель смещается синхронно, даже если мы идем с самого начала при updateAll
        if (newState == PointState.past && i == _firstActiveSpInd) {
          _firstActiveSpInd++;
        }

        // Лимит обновлений работает только для стандартного тика
        if (!updateAll && newState != PointState.past) {
          spUpdated++;
          if (spUpdated >= _spUpdateBatchSize) break;
        }
      }
    }

    // 3. Финализация тика
    _updateIsJump(_coveredDist, _prevCoveredDist);
  }

  ReadOnlySidePoint? get nextWayPoint {
    if (_wpIndices.isEmpty || _activeWpPtr < 0) return null;

    // 1. Проматываем пройденные вейпоинты.
    while (_activeWpPtr >= 0) {
      final int wpIndInAligned = _wpIndices[_activeWpPtr];
      final PointState state = _alignedSP.getState(wpIndInAligned);

      // Пропускаем, если вейпоинт удален ИЛИ мы его уже проехали
      if (state == PointState.deleted ||
          _alignedSP.getAbsDist(wpIndInAligned) <= _coveredDist) {
        // Ставим past только живым точкам
        if (state != PointState.deleted) {
          _alignedSP.setState(wpIndInAligned, PointState.past);
        }
        _activeWpPtr--;
      } else {
        break; // Нашли актуальный
      }
    }

    if (_activeWpPtr < 0) return null;

    final int wpIndInAligned = _wpIndices[_activeWpPtr];

    // 3. Актуализируем стейт.
    // разве если wpIndInAligned == _firstActiveSpInd это не значит, что вэйпоинт и так обновлён?
    if (wpIndInAligned == _firstActiveSpInd) {
      _alignedSP.setState(wpIndInAligned, PointState.next);
    } else {
      _alignedSP.setState(wpIndInAligned, PointState.onWay);
    }

    final Float64List flatMem = _alignedSP.buffer;
    final int offset = wpIndInAligned * 6;
    return ReadOnlySidePoint(
        Float64List.sublistView(flatMem, offset, offset + 6));
  }

  /// Возвращает плоский снапшот живых точек (Готов к TransferableTypedData)
  Float64List get activeSidePointsSnapshot {
    return _alignedSP.exportActiveSnapshot(_firstActiveSpInd);
  }

  /// Возвращает легковесную read-only проекцию активных точек.
  /// Генерирует объекты лениво, без промежуточных аллокаций.
  Iterable<ReadOnlySidePoint> get activeSidePoints sync* {
    final Float64List mem = _alignedSP.buffer;
    final int count = _alignedSP.length;

    for (int i = _firstActiveSpInd; i < count; i++) {
      if (_alignedSP.getState(i) != PointState.deleted) {
        final int offset = i * 6;
        yield ReadOnlySidePoint(
            Float64List.sublistView(mem, offset, offset + 6));
      }
    }
  }

  /// Возвращает все точки маршрута (включая пройденные), исключая удаленные.
  Iterable<ReadOnlySidePoint> get allSidePoints sync* {
    final Float64List mem = _alignedSP.buffer;
    final int count = _alignedSP.length;

    for (int i = 0; i < count; i++) {
      if (_alignedSP.getState(i) != PointState.deleted) {
        final int offset = i * 6;
        yield ReadOnlySidePoint(
            Float64List.sublistView(mem, offset, offset + 6));
      }
    }
  }

  double get routeLength => _routeLen;

  double get coveredDistance => _coveredDist;

  bool get isFinished => _routeLen - _coveredDist <= _finishThreshold;

  int get currentRoutePointIndex => _currRPInd;

  int get nextRoutePointIndex => _nextRPInd;

  int get previousRoutePointIndex => _prevRPInd;

  int get currentSegmentIndex => _currSegmInd;

  bool get isOnRoute => _isOnRoute;

  bool get isJump => _isJump && !(_isJump = false);
}
