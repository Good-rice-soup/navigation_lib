import 'dart:math';
import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'copy_policy.dart';
import 'geo_utils.dart';
import 'new_search_rect.dart';
import 'polyline_util.dart';
import 'route_transfer_objects.dart';
import 'search_rect.dart';
import 'side_point.dart';

/// `emaAlpha` - the smoothing factor (0.0 to 1.0) determining the weight of the
/// new coordinate when calculating weighted vector of movement.
/// * 1.0 = No smoothing (EMA instantly snaps to the new physical point).
/// * 0.0 = Complete freeze (EMA never updates).
/// A value of 0.5 provides a stable balance, effectively averaging the last few
/// updates.
class RouteManager {
  RouteManager({
    required RMConfig config,
    double additionalChecksDist = 100,
    double maxVectDeviationInDeg = 45,
    double sameCordConst = 0.00001,
    int amountSPToUpd = 40,
    double finishLineDist = 5,
    double emaAlpha = 0.5,
  })  : _route = config.route,
        _distFromStart = config.distFromStart,
        _segmentsLen = config.segmentsLen,
        _srBuffer = config.srBuffer,
        _alignedSP = config.alignedSP,
        _wpIndices = config.wpIndices,
        _routeLen = config.routeLen,
        _additionalChecksDist = additionalChecksDist,
        _cos = cos(maxVectDeviationInDeg * deg2rad),
        _sameCordConst = sameCordConst,
        _amountSPToUpd = amountSPToUpd,
        _finishLineDist = finishLineDist,
        _emaAlpha = emaAlpha,
        _emaLat = config.emaLat,
        _emaLng = config.emaLng,
        _prevLat = config.prevLat,
        _prevLng = config.prevLng;

  // naming:
  // RP - route point
  // SP - side point
  // WP - way point
  // SR - search rect

  final Float64List _route;
  final double _routeLen;
  double _coveredDist = 0;
  double _prevCoveredDist = 0;
  late LatLng _currRP;
  late LatLng _nextRP;
  late LatLng _prevRP;
  int _currRPInd = 0;
  int _nextRPInd = 1;
  int _prevRPInd = 0;
  int _currSegmInd = 0;
  int _prevSegmInd = 0;
  final double _finishLineDist;
  bool _isOnRoute = true;
  bool _isJump = false;
  final double _cos;
  final double _additionalChecksDist;
  final CopyPolicy _policy;
  final double _sameCordConst;
  final int _amountSPToUpd;

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
  int _blocker = 2;

  SidePoint? _nextWP;
  List<SidePoint> _wpList = [];

  // замена для _wpList
  final Int64List _wpIndices;

  //-----------------------------Methods----------------------------------------

  /// Updates previous location using EMA (Exponential Moving Average) Filter
  void _updateListOfPreviousLocations(LatLng currLoc) {
    final double currLat = currLoc.latitude;
    final double currLng = currLoc.longitude;

    final double diffLat = (_prevLat - currLat).abs();
    final double diffLng = (_prevLng - currLng).abs();

    if (diffLat < _sameCordConst && diffLng < _sameCordConst) return;

    // Обновляем виртуальную сглаженную точку
    _emaLat = currLat * _emaAlpha + _emaLat * (1.0 - _emaAlpha);
    _emaLng = currLng * _emaAlpha + _emaLng * (1.0 - _emaAlpha);

    // Сохраняем сырые координаты
    _prevLat = currLat;
    _prevLng = currLng;

    if (_blocker > 0) _blocker--;
  }

  double _distBtwn(LatLng curLoc, double spLat, double spLng, int curLocInd, int spInd) {
    // 1. Распаковываем текущую локацию
    final double curLat = curLoc.latitude;
    final double curLng = curLoc.longitude;

    // 2. Индексы начала сегмента и точки подключения (умножаем на 2 для плоского Float64List)
    final int segmStartOffset = curLocInd * 2;
    final int spOffset = spInd * 2;

    final double segmStartLat = _route[segmStartOffset];
    final double segmStartLng = _route[segmStartOffset + 1];

    final double connectionLat = _route[spOffset];
    final double connectionLng = _route[spOffset + 1];

    final bool isCurLocLast = curLocInd == (_route.length ~/ 2) - 1;

    // 3. Вычисляем вектор текущего местоположения (pV) без создания объектов-рекордов
    final double pVLat = curLat - segmStartLat;
    final double pVLng = curLng - segmStartLng;

    // Вектор направления сегмента (dV) и дополнительные точки
    final double dVLat;
    final double dVLng;
    final double additionalLat;
    final double additionalLng;

    if (isCurLocLast) {
      final int prevOffset = (curLocInd - 1) * 2;
      additionalLat = _route[prevOffset];
      additionalLng = _route[prevOffset + 1];

      dVLat = curLat - additionalLat;
      dVLng = curLng - additionalLng;
    } else {
      final int nextOffset = (curLocInd + 1) * 2;
      additionalLat = _route[nextOffset];
      additionalLng = _route[nextOffset + 1];

      dVLat = additionalLat - curLat;
      dVLng = additionalLng - curLng;
    }

    double dist;
    // Скалярное произведение
    final double dotProd = pVLat * dVLat + pVLng * dVLng;

    if (dotProd >= 0) {
      // _distFromStart — это одномерный массив (одна дистанция на точку), тут без смещений
      dist = _distFromStart[spInd] - _distFromStart[curLocInd + 1];
      dist += isCurLocLast
          ? getDistanceRaw(curLat, curLng, segmStartLat, segmStartLng)
          : getDistanceRaw(curLat, curLng, additionalLat, additionalLng);
    } else {
      dist = _distFromStart[spInd] - _distFromStart[curLocInd];
      dist += getDistanceRaw(curLat, curLng, segmStartLat, segmStartLng);
    }

    // Добавляем расстояние от точки подключения до самого сайдпоинта
    return dist + getDistanceRaw(spLat, spLng, connectionLat, connectionLng);
  }

  void _updateIsJump(double currentDist, double previousDist) {
    if (_isJump == true || _blocker > 0) return;
    _isJump = currentDist - previousDist > 100;
  }

  void deleteSidePoint(LatLng point) {
    _alignedSP.removeWhere((key, e) => e.point == point);
  }

  bool isPointOnRouteBySearchRect({required LatLng point}) {
    late bool isInRect;
    for (final int sr in _srMap.keys) {
      final SearchRect searchRect = _srMap[sr]!;
      isInRect = searchRect.isPointInRect(point);
      if (isInRect) {
        break;
      }
    }
    return isInRect;
  }

  /// returns a normalised weighted vector
  (double, double) _calcWeightedVector(LatLng currLoc) {
    // Вектор от сглаженной истории к текущей точке
    final double vx = currLoc.latitude - _emaLat;
    final double vy = currLoc.longitude - _emaLng;

    final double inversedLen = 1 / sqrt(vx * vx + vy * vy);
    return (vx * inversedLen, vy * inversedLen);
  }

  bool _isSegmValid(int ind, (double, double) vect, LatLng currLoc) {
    final SearchRect searchRect = _srMap[ind]!;
    final (double, double) segmVect = searchRect.normalisedSegmVect;

    //cos(alpha) = (dotProd)/(v1.len * v2.len) in our case both len = 1
    final double dotProd = vect.$1 * segmVect.$1 + vect.$2 * segmVect.$2;
    return _cos <= dotProd && searchRect.isPointInRect(currLoc);
  }

  int _searchCycle(int start, int end, (double, double) vect, LatLng currLoc) {
    for (int i = start; i < end; i++) {
      if (_isSegmValid(i, vect, currLoc)) return i;
    }
    return -1;
  }

  int _additionalChecks(LatLng currLoc, int start, (double, double) vect) {
    int newInd = start;
    double distCheck = 0;
    for (int i = start; i < _segmentsLen.length; i++) {
      if (distCheck >= _additionalChecksDist) break;
      if (!_isSegmValid(i, vect, currLoc)) return i - 1;
      distCheck += _segmentsLen[i]!;
      newInd = i;
    }
    return newInd;
  }

  int _findClosestSegmentIndex(LatLng currLoc) {
    final int mapLen = _srMap.length;
    final (double, double) motionVect = _blocker > 0
        ? _srMap[_prevSegmInd]!.normalisedSegmVect
        : _calcWeightedVector(currLoc);

    int closestSegmInd;
    bool isCurrLocFound;
    closestSegmInd = _searchCycle(_prevSegmInd, mapLen, motionVect, currLoc);
    isCurrLocFound = closestSegmInd != -1;

    if (!isCurrLocFound) {
      closestSegmInd = _searchCycle(0, _prevSegmInd, motionVect, currLoc);
      isCurrLocFound = closestSegmInd != -1;
    }

    if (isCurrLocFound && _blocker <= 0) {
      closestSegmInd = _additionalChecks(currLoc, closestSegmInd, motionVect);
    }
    _isOnRoute = isCurrLocFound;
    return closestSegmInd;
  }

  Map<int, SidePoint> updateSidePoints(LatLng currLoc, [int? currLocInd]) {
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int curLocInd;
    if (currLocInd != null) {
      _isOnRoute = currLocInd < 0 || currLocInd >= _route.length ? false : true;
      curLocInd = currLocInd;
    } else {
      curLocInd = _findClosestSegmentIndex(currLoc);
    }

    _updateListOfPreviousLocations(currLoc);
    if (_isOnRoute) {
      _currSegmInd = curLocInd;
      _prevSegmInd = curLocInd;
      final bool isLast = curLocInd < (_route.length - 1);
      final bool isFirst = curLocInd == 0;
      _currRP = _route[curLocInd];
      _nextRP = isLast ? _route[curLocInd + 1] : _route[curLocInd];
      _prevRP = isFirst ? _route[curLocInd] : _route[curLocInd - 1];
      _currRPInd = curLocInd;
      _nextRPInd = isLast ? curLocInd + 1 : curLocInd;
      _prevRPInd = isFirst ? curLocInd : curLocInd - 1;

      _prevCoveredDist = _coveredDist;
      _coveredDist =
          _distFromStart[_currRPInd]! + getDistance(_currRP, currLoc);

      bool firstNextFlag = true;
      for (final int i in _alignedSP.keys) {
        _alignedSP.update(i, (e) {
          final double dist =
              _distBtwn(currLoc, e.point, curLocInd, e.routeInd);

          final PointState state = e.routeInd <= curLocInd
              ? PointState.past
              : firstNextFlag && e.routeInd > curLocInd
                  ? (() {
                      firstNextFlag = false;
                      return PointState.next;
                    })()
                  : PointState.onWay;

          return e.update(newState: state, newDist: dist);
        });
      }

      _updateIsJump(_coveredDist, _prevCoveredDist);
      return _policy.sidePoints(_alignedSP);
    }
    return {};
  }

  Map<int, SidePoint> updateNSidePoints(LatLng currLoc, [int? currLocInd]) {
    if (_amountSPToUpd < 0) {
      throw ArgumentError("amountOfUpdatingSidePoints can't be less then 0");
    }
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int curLocInd;
    if (currLocInd != null) {
      _isOnRoute = currLocInd < 0 || currLocInd >= _route.length ? false : true;
      curLocInd = currLocInd;
    } else {
      curLocInd = _findClosestSegmentIndex(currLoc);
    }

    _updateListOfPreviousLocations(currLoc);
    if (_isOnRoute) {
      _currSegmInd = curLocInd;
      _prevSegmInd = curLocInd;
      final bool isLast = curLocInd < (_route.length - 1);
      final bool isFirst = curLocInd == 0;
      _currRP = _route[curLocInd];
      _nextRP = isLast ? _route[curLocInd + 1] : _route[curLocInd];
      _prevRP = isFirst ? _route[curLocInd] : _route[curLocInd - 1];
      _currRPInd = curLocInd;
      _nextRPInd = isLast ? curLocInd + 1 : curLocInd;
      _prevRPInd = isFirst ? curLocInd : curLocInd - 1;

      _prevCoveredDist = _coveredDist;
      _coveredDist =
          _distFromStart[_currRPInd]! + getDistance(_currRP, currLoc);

      final Map<int, SidePoint> newSPData = {};
      bool firstNextFlag = true;
      int spAmount = 0;

      for (final int i in _alignedSP.keys) {
        if (spAmount >= _amountSPToUpd) break;

        final SidePoint data = _alignedSP.update(i, (e) {
          if (e.state == PointState.past) return e;
          final double dist =
              _distBtwn(currLoc, e.point, curLocInd, e.routeInd);

          final PointState state = e.routeInd <= curLocInd
              ? PointState.past
              : firstNextFlag && e.routeInd > curLocInd
                  ? (() {
                      firstNextFlag = false;
                      return PointState.next;
                    })()
                  : PointState.onWay;

          return e.update(newState: state, newDist: dist);
        });

        if (data.state != PointState.past) {
          newSPData[i] = data;
          spAmount++;
        }
      }

      _updateIsJump(_coveredDist, _prevCoveredDist);
      return _policy.sidePoints(newSPData);
    }
    return {};
  }

  void updateCurrentLocation(LatLng currLoc, [int? currLocInd]) {
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int curLocInd;
    if (currLocInd != null) {
      _isOnRoute = currLocInd < 0 || currLocInd >= _route.length ? false : true;
      curLocInd = currLocInd;
    } else {
      curLocInd = _findClosestSegmentIndex(currLoc);
    }

    _updateListOfPreviousLocations(currLoc);
    if (_isOnRoute) {
      _currSegmInd = curLocInd;
      _prevSegmInd = curLocInd;
      final bool isLast = curLocInd < (_route.length - 1);
      final bool isFirst = curLocInd == 0;
      _currRP = _route[curLocInd];
      _nextRP = isLast ? _route[curLocInd + 1] : _route[curLocInd];
      _prevRP = isFirst ? _route[curLocInd] : _route[curLocInd - 1];
      _currRPInd = curLocInd;
      _nextRPInd = isLast ? curLocInd + 1 : curLocInd;
      _prevRPInd = isFirst ? curLocInd : curLocInd - 1;

      _prevCoveredDist = _coveredDist;
      _coveredDist =
          _distFromStart[_currRPInd]! + getDistance(_currRP, currLoc);
      _updateIsJump(_coveredDist, _prevCoveredDist);
    }
  }

  SidePoint? get nextWayPoint {
    if (_nextWP != null) {
      SidePoint? nextSP;
      for (final SidePoint p in _alignedSP.values) {
        if (p.state == PointState.next) {
          nextSP = p;
          break;
        }
      }
      // TODO: replace _prevCurrLocs by prevLat prevLng
      final LatLng currLoc =
          _prevCurrLocs.isEmpty ? _currRP : _prevCurrLocs.first;

      if (nextSP != null) {
        if (nextSP.point == _nextWP!.point) return nextSP.copy();
        if (nextSP.routeInd <= _nextWP!.routeInd) {
          final double dist =
              _distBtwn(currLoc, _nextWP!.point, _currRPInd, _nextWP!.routeInd);
          _nextWP!.update(newState: PointState.onWay, newDist: dist);
          return _nextWP!.copy();
        } else {
          while (_wpList.length > 1) {
            if (_nextWP!.routeInd < nextSP.routeInd) {
              _wpList.removeLast();
              _nextWP = _wpList.last;
            } else {
              break;
            }
          }

          if (nextSP.point == _nextWP!.point) return nextSP.copy();

          final double dist =
              _distBtwn(currLoc, _nextWP!.point, _currRPInd, _nextWP!.routeInd);
          _nextWP!.update(newState: PointState.onWay, newDist: dist);
          return _nextWP!.copy();
        }
      }

      final double dist =
          _distBtwn(currLoc, _nextWP!.point, _currRPInd, _nextWP!.routeInd);
      _nextWP!.update(newState: PointState.past, newDist: dist);
      return _nextWP!.copy();
    }
    return null;
  }

  double get routeLength => _routeLen;

  double get coveredDistance => _coveredDist;

  bool get isFinished => _routeLen - _coveredDist <= _finishLineDist;

  int get currentRoutePointIndex => _currRPInd;

  int get nextRoutePointIndex => _nextRPInd;

  int get previousRoutePointIndex => _prevRPInd;

  int get currentSegmentIndex => _currSegmInd;

  bool get isOnRoute => _isOnRoute;

  bool get isJump => _isJump && !(_isJump = false);

  Map<int, SidePoint> get sidePointsData => _policy.sidePoints(_alignedSP);
}
