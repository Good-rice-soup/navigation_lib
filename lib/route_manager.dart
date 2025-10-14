import 'dart:collection';
import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'copy_policy.dart';
import 'geo_utils.dart';
import 'polyline_util.dart';
import 'search_rect.dart';
import 'side_point.dart';

class RouteManager {
  RouteManager({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
    required List<LatLng> wayPoints,
    double searchRectWidth = 10,
    double searchRectExtension = 5,
    double additionalChecksDist = 100,
    double maxVectDeviationInDeg = 45,
    double sameCordConst = 0.00001,
    double maxDistanceToSidePoint = 100.0,
    int amountSPToUpd = 40,
    double finishLineDist = 5,
    int lengthOfLists = 2,
    CopyPolicy? policy,
    int ignoreSimplificationIfLess = 300,
  }) {
    _route = checkForDuplications(route);
    _searchRectWidth = searchRectWidth;
    _searchRectExt = searchRectExtension;
    _additionalChecksDist = additionalChecksDist;
    _cos = cos(toRadians(maxVectDeviationInDeg));
    _sameCordConst = sameCordConst;
    _maxDistToSP = maxDistanceToSidePoint;
    _amountSPToUpd = amountSPToUpd;
    _finishLineDist = finishLineDist;
    _lengthOfLists = lengthOfLists >= 1
        ? lengthOfLists
        : throw ArgumentError('Length of lists must be equal or more then 1');
    _policy = policy ?? CopyPolicy();

    if (_route.length < 2) {
      throw ArgumentError('Your route contains less than 2 points');
    } else {
      int pointIndex = 0;
      for (int i = pointIndex; i < (_route.length - 1); i++) {
        _distFromStart[pointIndex++] = _routeLen;
        final double dist = getDistance(_route[i], _route[i + 1]);
        _routeLen += dist;
        _segmentsLen[i] = dist;

        _srMap[i] = SearchRect(
          start: _route[i],
          end: _route[i + 1],
          rectWidth: _searchRectWidth,
          rectExt: _searchRectExt,
        );
      }
      _distFromStart[pointIndex] = _routeLen;
      // By default we think that we are starting at the beginning of the route
      _currRP = _route[0];
      _nextRP = _route[1];

      if (sidePoints.isNotEmpty || wayPoints.isNotEmpty) {
        final Map<int, int> mapping = {};
        final double tolerance = _maxDistToSP / 2;
        final List<LatLng> simplifiedRoute = rdpRouteSimplifier(
            _route, tolerance,
            ignoreIfLess: ignoreSimplificationIfLess, mapping: mapping);
        final Map<int, SearchRect> simplifiedSRMap = {};
        final double searchFactor = _maxDistToSP * 1.5;

        for (int i = 0; i < (simplifiedRoute.length - 1); i++) {
          simplifiedSRMap[i] = SearchRect(
            start: simplifiedRoute[i],
            end: simplifiedRoute[i + 1],
            rectWidth: searchFactor,
            rectExt: searchFactor,
          );
        }

        final List<({int ind, LatLng point, double minDist})>
            indexedAndCuttedSP = _indexingAndCutting(
                wayPoints, sidePoints, simplifiedSRMap, mapping);
        _aligning(indexedAndCuttedSP);
        _mapping(indexedAndCuttedSP, wayPoints);
      }
      _generatePointsAndWeights();
    }
  }

  // naming:
  // RP - route point
  // SP - side point
  // WP - way point
  // SR - search rect

  late final List<LatLng> _route;
  double _routeLen = 0;
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
  late final double _finishLineDist;
  bool _isOnRoute = true;
  bool _isJump = false;
  late final double _searchRectWidth;
  late final double _searchRectExt;
  late final double _maxDistToSP;
  late final double _cos;
  late final double _additionalChecksDist;
  late final CopyPolicy _policy;
  late double _sameCordConst;
  int _amountSPToUpd = 0;

  /// {segment index in the route, search rect}
  final Map<int, SearchRect> _srMap = {};

  /// {index of aligned side point, side point}
  /// ``````
  /// In function works with a beginning of segment.
  final Map<int, SidePoint> _alignedSP = {};

  /// {segment index in the route, distance traveled form start}
  final Map<int, double> _distFromStart = {};

  /// {segment index in the route, segment length}
  final Map<int, double> _segmentsLen = {};

  /// [previous current location, previous previous current location, so on]
  /// ``````
  /// They are used for weighted vector sum.
  final List<LatLng> _listOfPrevCurrLoc = [];
  final List<double> _listOfWeights = [];
  late final int _lengthOfLists;

  /// exists to let position update at least 2 times (need to create vector)
  int _blocker = 2;

  SidePoint? _nextWP;
  List<SidePoint> _wpList = [];

  //-----------------------------Methods----------------------------------------

  /// Checks the path for duplicate coordinates, and returns the path without duplicates.
  static List<LatLng> checkForDuplications(List<LatLng> route) {
    final List<LatLng> newRoute = [];
    if (route.isNotEmpty) {
      newRoute.add(route[0]);
      for (int i = 1; i < route.length; i++) {
        if (route[i] != route[i - 1]) {
          newRoute.add(route[i]);
        }
      }
    }
    return newRoute;
  }

  List<({int ind, LatLng point, double minDist})> _indexingAndCutting(
      List<LatLng> wayPoints,
      List<LatLng> sidePoints,
      Map<int, SearchRect> srMap,
      Map<int, int> mapping) {
    final List<({int ind, LatLng point, double minDist})> passedSP = [];
    int wpStartIndex = 0;

    for (final LatLng wp in wayPoints) {
      int ind = wpStartIndex;
      double minDist = double.infinity;
      final List<int> insideSegm = [];

      for (int i = 0; i < srMap.length; i++) {
        final SearchRect sr = srMap[i]!;
        if (sr.isPointInRect(wp)) insideSegm.add(i);
      }

      for (final int segmInd in insideSegm) {
        final int start = mapping[segmInd]!;
        final int end = mapping[segmInd + 1]!;

        for (int rpInd = start; rpInd <= end; rpInd++) {
          final double dist = getDistance(wp, _route[rpInd]);
          if (dist < minDist) {
            minDist = dist;
            ind = rpInd;
            wpStartIndex = rpInd;
          }
        }
      }

      if (minDist == double.infinity) {
        for (int i = 0; i < _route.length; i++) {
          final double dist = getDistance(wp, _route[i]);
          if (dist < minDist) {
            minDist = dist;
            ind = i;
            wpStartIndex = i;
          }
        }
      }
      passedSP.add((ind: ind, point: wp, minDist: minDist));
    }

    for (final LatLng sp in sidePoints) {
      // index of closes route point
      int ind = -1;
      double minDist = double.infinity;
      final List<int> insideSegm = [];

      for (int i = 0; i < srMap.length; i++) {
        final SearchRect sr = srMap[i]!;
        if (sr.isPointInRect(sp)) insideSegm.add(i);
      }

      if (insideSegm.isNotEmpty) {
        for (final int segmInd in insideSegm) {
          final int start = mapping[segmInd]!;
          final int end = mapping[segmInd + 1]!;

          for (int rpInd = start; rpInd <= end; rpInd++) {
            final dist = getDistance(sp, _route[rpInd]);
            if (dist <= _maxDistToSP && dist < minDist) {
              minDist = dist;
              ind = rpInd;
            }
          }
        }
        if (ind != -1) passedSP.add((ind: ind, point: sp, minDist: minDist));
      }
    }
    return passedSP;
  }

  void _aligning(List<({int ind, LatLng point, double minDist})> indexedSP) {
    indexedSP.sort((a, b) {
      final indCompare =
          (a.ind == 0 ? -1 : a.ind).compareTo(b.ind == 0 ? -1 : b.ind);

      if (indCompare != 0) return indCompare;
      return a.ind == 0
          ? -a.minDist.compareTo(b.minDist)
          : a.minDist.compareTo(b.minDist);
    });
  }

  double _distBtwn(LatLng curLoc, LatLng sp, int curLocInd, int spInd) {
    final LatLng segmStart = _route[curLocInd];
    final LatLng connectionPoint = _route[spInd];
    final bool isCurLocLast = curLocInd == _route.length - 1;
    final LatLng additionalPoint;

    // direction vector
    final ({double lat, double lng}) dV;
    // point vector
    final ({double lat, double lng}) pV = (
      lat: curLoc.latitude - segmStart.latitude,
      lng: curLoc.longitude - segmStart.longitude
    );
    if (isCurLocLast) {
      additionalPoint = _route[curLocInd - 1];
      dV = (
        lat: curLoc.latitude - additionalPoint.latitude,
        lng: curLoc.longitude - additionalPoint.longitude
      );
    } else {
      additionalPoint = _route[curLocInd + 1];
      dV = (
        lat: additionalPoint.latitude - curLoc.latitude,
        lng: additionalPoint.longitude - curLoc.longitude
      );
    }

    double dist;
    final double dotProd = pV.lat * dV.lat + pV.lng * dV.lng;
    if (dotProd >= 0) {
      dist = _distFromStart[spInd]! - _distFromStart[curLocInd + 1]!;
      dist += isCurLocLast
          ? getDistance(curLoc, segmStart)
          : getDistance(curLoc, additionalPoint);
    } else {
      dist = _distFromStart[spInd]! - _distFromStart[curLocInd]!;
      dist += getDistance(curLoc, segmStart);
    }
    return dist + getDistance(sp, connectionPoint);
  }

  void _mapping(List<({int ind, LatLng point, double minDist})> alignedSPData,
      List<LatLng> wayPoints) {
    int index = 0;
    bool firstNextFlag = true;

    for (final ({int ind, LatLng point, double minDist}) sp in alignedSPData) {
      final int ind = sp.ind;
      final LatLng sidePoint = sp.point;
      final double minDist = sp.minDist;

      final bool isLast = ind == _route.length - 1;
      final LatLng nextP = isLast ? _route[ind] : _route[ind + 1];
      final LatLng closestP = isLast ? _route[ind - 1] : _route[ind];

      final double skew = skewProduction(closestP, nextP, sidePoint);
      final PointPosition position =
          skew <= 0 ? PointPosition.right : PointPosition.left;

      final PointState state = ind <= _currRPInd
          ? PointState.past
          : firstNextFlag && ind > _currRPInd
              ? (() {
                  firstNextFlag = false;
                  return PointState.next;
                })()
              : PointState.onWay;

      final double dist = _distFromStart[ind]! + minDist;

      _alignedSP[index] = SidePoint(
          point: sidePoint,
          routeInd: ind,
          position: position,
          state: state,
          dist: dist);
      index++;

      if (wayPoints.contains(sidePoint)) {
        _wpList.add(SidePoint(
            point: sidePoint,
            routeInd: ind,
            position: position,
            state: state,
            dist: dist));
      }
    }
    _wpList = _wpList.reversed.toList();
    if (_wpList.isNotEmpty) _nextWP = _wpList.last;
  }

  void _generatePointsAndWeights() {
    for (int i = 0; i < _lengthOfLists; i++) {
      _listOfPrevCurrLoc.add(_route[0]);
      _listOfWeights.add(1 / pow(2, i + 1));
    }
    _listOfWeights[0] += 1 / pow(2, _lengthOfLists);
  }

  void _updateListOfPreviousLocations(LatLng currLoc) {
    final LatLng prevLoc = _listOfPrevCurrLoc.first;
    final double diffLat = (prevLoc.latitude - currLoc.latitude).abs();
    final double diffLng = (prevLoc.longitude - currLoc.longitude).abs();

    if (diffLat >= _sameCordConst || diffLng >= _sameCordConst) {
      for (int i = _listOfPrevCurrLoc.length - 1; i > 0; i--) {
        _listOfPrevCurrLoc[i] = _listOfPrevCurrLoc[i - 1];
      }
      _listOfPrevCurrLoc[0] = currLoc;
      if (_blocker > 0) _blocker--;
    }
  }

  void _updateIsJump(double currentDist, double previousDist) {
    if (_isJump == true) return;
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
    double vx = 0;
    double vy = 0;
    for (int i = 0; i < _lengthOfLists; i++) {
      final LatLng prevLoc = _listOfPrevCurrLoc[i];
      final double coeff = _listOfWeights[i];

      vx = vx + coeff * (currLoc.latitude - prevLoc.latitude);
      vy = vy + coeff * (currLoc.longitude - prevLoc.longitude);
    }
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

    if (_isOnRoute) {
      _updateListOfPreviousLocations(currLoc);

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

    if (_isOnRoute) {
      _updateListOfPreviousLocations(currLoc);

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
      final LatLng currLoc =
          _listOfPrevCurrLoc.isEmpty ? _currRP : _listOfPrevCurrLoc.first;

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

  List<LatLng> get route => _policy.route(_route);

  double get routeLength => _routeLen;

  double get coveredDistance => _coveredDist;

  bool get isFinished => _routeLen - _coveredDist <= _finishLineDist;

  LatLng get currentRoutePoint => _currRP;

  LatLng get nextRoutePoint => _nextRP;

  LatLng get previousRoutePoint => _prevRP;

  int get currentRoutePointIndex => _currRPInd;

  int get nextRoutePointIndex => _nextRPInd;

  int get previousRoutePointIndex => _prevRPInd;

  int get currentSegmentIndex => _currSegmInd;

  bool get isOnRoute => _isOnRoute;

  bool get isJump => _isJump && !(_isJump = false);

  Map<int, SearchRect> get searchRectMap => _policy.searchRect(_srMap);

  Map<int, SidePoint> get sidePointsData => _policy.sidePoints(_alignedSP);

  CopyPolicy get policy => _policy;

  UnmodifiableMapView<int, double> get distanceFromStart =>
      UnmodifiableMapView(_distFromStart);

  UnmodifiableMapView<int, double> get segmentsLength =>
      UnmodifiableMapView(_segmentsLen);
}
