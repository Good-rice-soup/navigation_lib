import 'dart:math';
import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';
import 'search_rect.dart';
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
  })  : _maxDevCos = cos(maxDeviationDeg * deg2rad),
        _movementThreshold = movementThreshold,
        _spUpdateBatchSize = spUpdateBatchSize,
        _finishThreshold = finishThreshold,
        _emaAlpha = emaSmoothingFactor,
        _jumpThreshold = jumpThreshold,
        _route = config.route,
        _distFromStart = config.distFromStart,
        _segmentsLen = config.segmentsLen,
        _srBuffer = config.srBuffer,
        _alignedSP = config.alignedSP,
        _spStates = config.spStates,
        _wpIndices = config.wpIndices,
        _routeLen = config.routeLen,
        _emaLat = config.progress.emaLat,
        _emaLng = config.progress.emaLng,
        _prevLat = config.progress.prevLat,
        _prevLng = config.progress.prevLng,
        _currRPInd = config.progress.currRPInd,
        _nextRPInd = config.progress.nextRPInd,
        _prevRPInd = config.progress.prevRPInd,
        _currSegmInd = config.progress.currSegmInd,
        _prevSegmInd = config.progress.prevSegmInd,
        _coveredDist = config.progress.coveredDist,
        _prevCoveredDist = config.progress.prevCoveredDist,
        _initTicks = config.progress.initTicks,
        _firstActiveSpInd = config.progress.firstActiveSpInd,
        _activeWpPtr = config.progress.activeWpPtr,
        _isOnRoute = config.progress.isOnRoute,
        _isJump = config.progress.isJump;

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

  /// Пространственные данные точек маршрута
  final RawSidePointsBuffer _alignedSP;

  /// Флаги состояний точек маршрута
  final SidePointStates _spStates;

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

  /// The last received raw physical latitude and longitude.
  double _prevLat;
  double _prevLng;

  /// exists to let position update at least 2 times (need to create vector)
  int _initTicks = 2;

  int _firstActiveSpInd = 0;

  final double _jumpThreshold;

  int _activeWpPtr = 0;

  final Int64List _wpIndices;

  //-----------------------------Methods----------------------------------------

  /// Updates previous location using EMA (Exponential Moving Average) Filter
  void _updateListOfPreviousLocations(double currLat, double currLng) {
    // КОЛД-СТАРТ: Первые два тика просто телепортируем EMA в текущую точку,
    // чтобы не тащить за собой шлейф от начала пути.
    if (_initTicks > 0) {
      _emaLat = currLat;
      _emaLng = currLng;
      _prevLat = currLat;
      _prevLng = currLng;
      _initTicks--;
      return;
    }

    final double diffLat = (_prevLat - currLat).abs();
    final double diffLng = (_prevLng - currLng).abs();

    // Троттлинг: игнорируем микро-смещения (шум GPS, когда стоим на месте)
    if (diffLat < _movementThreshold && diffLng < _movementThreshold) return;

    // Нормальное сглаживание: тянем точку за собой
    _emaLat = currLat * _emaAlpha + _emaLat * (1.0 - _emaAlpha);
    _emaLng = currLng * _emaAlpha + _emaLng * (1.0 - _emaAlpha);

    _prevLat = currLat;
    _prevLng = currLng;
  }

  void _updateIsJump(double currentDist, double previousDist) {
    if (_isJump == true || _initTicks > 0) return;
    _isJump = currentDist - previousDist > _jumpThreshold;
  }

  /// Логическое удаление точки. Сохраняет целостность _wpIndices.
  void deleteSidePoint(double pLat, double pLng) {
    _alignedSP.removeByPoint(pLat, pLng, _spStates);
  }

  bool isPointOnRoute({required LatLng point}) {
    final double pLat = point.latitude;
    final double pLng = point.longitude;

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

        final proj = getProjectionRaw(curLat, curLng, aLat, aLng, bLat, bLng);

        final double distRadSq =
            getDistanceRadSq(curLat, curLng, proj.lat, proj.lng);

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

    int closestSegmInd =
        _searchCycle(_prevSegmInd, mapLen, vLat, vLng, curLat, curLng);

    if (closestSegmInd == -1) {
      closestSegmInd =
          _searchCycle(0, _prevSegmInd, vLat, vLng, curLat, curLng);
    }

    _isOnRoute = closestSegmInd != -1;
    return closestSegmInd;
  }

  void updatePosition(LatLng currLoc, {SPUpdMode spMode = SPUpdMode.all}) {
    final double curLat = currLoc.latitude;
    final double curLng = currLoc.longitude;

    final int curLocInd = _findClosestSegmentIndex(curLat, curLng);

    _updateListOfPreviousLocations(curLat, curLng);

    if (!_isOnRoute) return;

    _currSegmInd = curLocInd;
    _prevSegmInd = max(curLocInd - 1, 0);

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

    final proj =
        getProjectionRaw(curLat, curLng, rpLat, rpLng, nextRpLat, nextRpLng);
    final double abSegLen = _segmentsLen[_currSegmInd];

    _prevCoveredDist = _coveredDist;
    _coveredDist = _distFromStart[_currSegmInd] + (proj.t * abSegLen);

    if (spMode != SPUpdMode.none) {
      final bool updateAll = spMode == SPUpdMode.all;
      final int startInd = updateAll ? 0 : _firstActiveSpInd;

      int processedCount = 0;
      bool firstNextFlag = true;

      for (int i = startInd; i < _alignedSP.length; i++) {
        final PointState currentState = _spStates.getState(i);

        if (currentState == PointState.deleted) {
          if (i == _firstActiveSpInd) _firstActiveSpInd++;
          continue;
        }

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

        if (currentState != newState) _spStates.setState(i, newState);

        if (newState == PointState.past && i == _firstActiveSpInd) {
          _firstActiveSpInd++;
        }

        if (!updateAll && newState != PointState.past) {
          processedCount++;
          if (processedCount >= _spUpdateBatchSize) break;
        }
      }
    }

    _updateIsJump(_coveredDist, _prevCoveredDist);
  }

  UISidePointsBuffer? get nextWayPoint {
    if (_wpIndices.isEmpty || _activeWpPtr >= _wpIndices.length) return null;

    // Идем вперед по массиву от 0 до length
    while (_activeWpPtr < _wpIndices.length) {
      final int wpIndInAligned = _wpIndices[_activeWpPtr];
      final PointState state = _spStates.getState(wpIndInAligned);

      if (state == PointState.deleted ||
          _alignedSP.getAbsDist(wpIndInAligned) <= _coveredDist) {
        if (state != PointState.deleted) {
          _spStates.setState(wpIndInAligned, PointState.past);
        }
        _activeWpPtr++;
      } else {
        break;
      }
    }

    if (_activeWpPtr >= _wpIndices.length) return null;

    final int wpIndInAligned = _wpIndices[_activeWpPtr];

    if (wpIndInAligned == _firstActiveSpInd) {
      _spStates.setState(wpIndInAligned, PointState.next);
    } else {
      _spStates.setState(wpIndInAligned, PointState.onWay);
    }

    final Float64List uiBuffer = Float64List(6);
    final int srcOffset = wpIndInAligned * 5;

    uiBuffer[0] = _alignedSP.buffer[srcOffset];
    uiBuffer[1] = _alignedSP.buffer[srcOffset + 1];
    uiBuffer[2] = _alignedSP.buffer[srcOffset + 2];
    uiBuffer[3] = _alignedSP.buffer[srcOffset + 3];
    uiBuffer[4] = _alignedSP.buffer[srcOffset + 4];
    uiBuffer[5] = _spStates.getAll(wpIndInAligned).toDouble();

    return UISidePointsBuffer(uiBuffer);
  }

  /// Приватный хелпер для безопасного клонирования массива с 8-байтным выравниванием.
  /// Создает копию байтов, сохраняя 8-байтное аппаратное выравнивание памяти.
  SidePointStates _cloneAlignedU8() {
    // Длина _spStates уже кратна 8, просто делим.
    final int doublesCount = _spStates.length ~/ 8;

    // КРИТИЧНО: Аллоцируем именно через Float64List.
    // Если выделить память через Uint8List(_spStates.length), Dart может положить
    // её по невыровненному адресу в RAM. Тогда на ARM-архитектурах (Android/iOS)
    // при попытке прочитать это как Float64List приложение крашнется.
    final Float64List alignedCopy = Float64List(doublesCount);
    final Uint8List byteView = Uint8List.view(alignedCopy.buffer)
      ..setRange(0, _spStates.length, _spStates.buffer);

    return SidePointStates(byteView);
  }

  /// Экспортирует мутабельное состояние.
  RMState exportState() {
    return RMState(
      spStates: _cloneAlignedU8(), // Менеджер защищает свою память
      progress: RouteProgress(
        emaLat: _emaLat,
        emaLng: _emaLng,
        prevLat: _prevLat,
        prevLng: _prevLng,
        currRPInd: _currRPInd,
        nextRPInd: _nextRPInd,
        prevRPInd: _prevRPInd,
        currSegmInd: _currSegmInd,
        prevSegmInd: _prevSegmInd,
        coveredDist: _coveredDist,
        prevCoveredDist: _prevCoveredDist,
        initTicks: _initTicks,
        firstActiveSpInd: _firstActiveSpInd,
        activeWpPtr: _activeWpPtr,
        isOnRoute: _isOnRoute,
        isJump: _isJump,
      ),
    );
  }

  /// Возвращает ВСЕ сайдпоинты (кроме удаленных), начиная с индекса 0 и до конца.
  UISidePointsBuffer get allSidePoints {
    int aliveCount = 0;
    final int count = _alignedSP.length;

    // Считаем все живые точки от самого начала
    for (int i = 0; i < count; i++) {
      if (_spStates.getState(i) != PointState.deleted) aliveCount++;
    }

    if (aliveCount == 0) return UISidePointsBuffer(Float64List(0));

    final Float64List uiBuffer = Float64List(aliveCount * 6);
    int destOffset = 0;

    for (int i = 0; i < count; i++) {
      if (_spStates.getState(i) != PointState.deleted) {
        final int srcOffset = i * 5;

        uiBuffer[destOffset++] = _alignedSP.buffer[srcOffset];
        uiBuffer[destOffset++] = _alignedSP.buffer[srcOffset + 1];
        uiBuffer[destOffset++] = _alignedSP.buffer[srcOffset + 2];
        uiBuffer[destOffset++] = _alignedSP.buffer[srcOffset + 3];
        uiBuffer[destOffset++] = _alignedSP.buffer[srcOffset + 4];

        uiBuffer[destOffset++] = _spStates.getAll(i).toDouble();
      }
    }
    return UISidePointsBuffer(uiBuffer);
  }

  /// Возвращает батч только из тех точек, которые идут после `next` (включая саму `next`).
  /// Количество ограничено параметром `_spUpdateBatchSize`.
  UISidePointsBuffer get updatedSidePoints {
    int count = 0;
    int startIndex = _firstActiveSpInd; // Индекс точки, которая сейчас next
    final int maxLen = _alignedSP.length;

    // Считаем реальное количество живых точек в батче
    int tempI = startIndex;
    while (tempI < maxLen && count < _spUpdateBatchSize) {
      if (_spStates.getState(tempI) != PointState.deleted) {
        count++;
      }
      tempI++;
    }

    if (count == 0) return UISidePointsBuffer(Float64List(0));

    final Float64List uiBuffer = Float64List(count * 6);
    int destOffset = 0;
    int processed = 0;

    // Сшиваем данные только для этого среза
    while (startIndex < maxLen && processed < count) {
      if (_spStates.getState(startIndex) != PointState.deleted) {
        final int srcOffset = startIndex * 5;

        uiBuffer[destOffset++] = _alignedSP.buffer[srcOffset];
        uiBuffer[destOffset++] = _alignedSP.buffer[srcOffset + 1];
        uiBuffer[destOffset++] = _alignedSP.buffer[srcOffset + 2];
        uiBuffer[destOffset++] = _alignedSP.buffer[srcOffset + 3];
        uiBuffer[destOffset++] = _alignedSP.buffer[srcOffset + 4];

        uiBuffer[destOffset++] = _spStates.getAll(startIndex).toDouble();
        processed++;
      }
      startIndex++;
    }
    return UISidePointsBuffer(uiBuffer);
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
