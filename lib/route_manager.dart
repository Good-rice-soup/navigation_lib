import 'dart:collection';
import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'copy_policy.dart';
import 'geo_utils.dart';
import 'polyline_util.dart';
import 'quad_tree.dart';
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
    double boundsExt = 0.000000001,
    int ignoreSimplificationIfLess = 300,
    double insertPrecision = 0.00001,
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
        final double dist = getDistance(p1: _route[i], p2: _route[i + 1]);
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
        final LatLngBounds bounds = LatLngBounds(
          southwest: const LatLng(-90, -180),
          northeast: LatLng(90, 180 - boundsExt),
        );
        final Map<int, int> mapping = {};
        final double tolerance = _maxDistToSP / 2;
        final List<LatLng> simplifiedRoute = rdpRouteSimplifier(
            _route, tolerance,
            ignoreIfLess: ignoreSimplificationIfLess, mapping: mapping);

        final int len = simplifiedRoute.length;
        final QuadTree tree = QuadTree(bounds, insertPrecision);
        for (int i = 0; i < len; i++) {
          tree.insert(NodeData(simplifiedRoute[i], i));
        }

        final List<({int ind, LatLng point, double minDist})>
            indexedAndCuttedSP = _indexingAndCutting(
                wayPoints, sidePoints.toSet(), tree, mapping, len);
        _aligning(indexedAndCuttedSP);
        _mapping(indexedAndCuttedSP);
      }
      _generatePointsAndWeights();
    }
  }

  // naming:
  // RP - route point
  // SP - side point
  // SR - search rect

  late final List<LatLng> _route;
  double _routeLen = 0;
  double _coveredDist = 0;
  double _prevCoveredDist = 0;
  late LatLng _currRP;
  late LatLng _nextRP;
  int _currRPInd = 0;
  int _nextRPInd = 1;
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
    Set<LatLng> sidePoints,
    QuadTree tree,
    Map<int, int> mapping,
    int simpleRouteLen,
  ) {
    final List<({int ind, LatLng point, double minDist})> passedSP = [];
    int wpStartIndex = 0;

    for (final LatLng wp in wayPoints) {
      int ind = wpStartIndex;
      double minDist = double.infinity;
      final List<int> pointsInd = [...tree.search(wp).map((e) => e.index)];

      for (final int pointInd in pointsInd) {
        final bool isStart = pointInd == 0;
        final bool isEnd = pointInd == simpleRouteLen - 1;
        final int start = mapping[isStart ? pointInd : pointInd - 1]!;
        final int end = mapping[isEnd ? pointInd : pointInd + 1]!;

        for (int rpInd = start; rpInd <= end; rpInd++) {
          final dist = getDistance(p1: wp, p2: _route[rpInd]);
          if (dist < minDist) {
            minDist = dist;
            ind = rpInd;
            wpStartIndex = rpInd;
          }
        }
      }
      passedSP.add((ind: ind, point: wp, minDist: minDist));
    }

    for (final LatLng sp in sidePoints) {
      // index of closes route point
      int ind = -1;
      double minDist = double.infinity;
      final List<int> pointsInd = [...tree.search(sp).map((e) => e.index)];

      for (final int pointInd in pointsInd) {
        final bool isStart = pointInd == 0;
        final bool isEnd = pointInd == simpleRouteLen - 1;
        final int start = mapping[isStart ? pointInd : pointInd - 1]!;
        final int end = mapping[isEnd ? pointInd : pointInd + 1]!;

        for (int rpInd = start; rpInd <= end; rpInd++) {
          final dist = getDistance(p1: sp, p2: _route[rpInd]);
          if (dist <= _maxDistToSP && dist < minDist) {
            minDist = dist;
            ind = rpInd;
          }
        }
      }
      if (ind != -1) passedSP.add((ind: ind, point: sp, minDist: minDist));
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

  /// A - start, B - end, aInd and bInd - A and B index on route
  double _distBtwn(LatLng A, LatLng B, int aInd, int bInd, {double? dst}) {
    double dist = _distFromStart[bInd]! - _distFromStart[aInd]!;
    if (dst != null) {
      return dist + dst;
    } else {
      final LatLng aOnRoute = _route[aInd];
      final LatLng bOnRoute = _route[bInd];

      if (A != aOnRoute) dist += getDistance(p1: A, p2: aOnRoute);
      if (B != bOnRoute) dist += getDistance(p1: B, p2: bOnRoute);
      return dist;
    }
  }

  void _mapping(List<({int ind, LatLng point, double minDist})> alignedSPData) {
    int index = 0;
    bool firstNextFlag = true;
    final LatLng currRP = _route[_currRPInd];

    for (final ({int ind, LatLng point, double minDist}) sp in alignedSPData) {
      final int ind = sp.ind;
      final LatLng sidePoint = sp.point;
      final double minDist = sp.minDist;

      final bool isLast = ind < _route.length;
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

      final double dist =
          _distBtwn(currRP, sidePoint, _currRPInd, ind, dst: minDist);

      _alignedSP[index] = SidePoint(
          point: sidePoint,
          routeInd: ind,
          position: position,
          state: state,
          dist: dist);
      index++;
    }
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
      currLocInd < 0 || currLocInd >= _route.length
          ? _isOnRoute = false
          : _isOnRoute = true;

      curLocInd = currLocInd;
    } else {
      curLocInd = _findClosestSegmentIndex(currLoc);
    }

    if (_isOnRoute) {
      _prevCoveredDist = _coveredDist;
      _coveredDist = _distBtwn(_route.first, currLoc, 0, curLocInd);
      _currSegmInd = curLocInd;

      _prevSegmInd = curLocInd;
      _updateListOfPreviousLocations(currLoc);
      final bool flag = curLocInd < (_route.length - 1);
      _currRP = _route[curLocInd];
      _nextRP = flag ? _route[curLocInd + 1] : _route[curLocInd];
      _currRPInd = curLocInd;
      _nextRPInd = flag ? curLocInd + 1 : curLocInd;

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
      currLocInd < 0 || currLocInd >= _route.length
          ? _isOnRoute = false
          : _isOnRoute = true;

      curLocInd = currLocInd;
    } else {
      curLocInd = _findClosestSegmentIndex(currLoc);
    }

    if (_isOnRoute) {
      _prevCoveredDist = _coveredDist;
      _coveredDist = _distBtwn(_route.first, currLoc, 0, curLocInd);
      _currSegmInd = curLocInd;

      _prevSegmInd = curLocInd;
      _updateListOfPreviousLocations(currLoc);
      final bool flag = curLocInd < (_route.length - 1);
      _currRP = _route[curLocInd];
      _nextRP = flag ? _route[curLocInd + 1] : _route[curLocInd];
      _currRPInd = curLocInd;
      _nextRPInd = flag ? curLocInd + 1 : curLocInd;

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

  void updateCurrentLocation(LatLng curLoc, [int? curLocInd]) {
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int currLocInd;
    if (curLocInd != null) {
      curLocInd < 0 || curLocInd >= _route.length
          ? _isOnRoute = false
          : _isOnRoute = true;

      currLocInd = curLocInd;
    } else {
      currLocInd = _findClosestSegmentIndex(curLoc);
    }

    if (_isOnRoute) {
      _prevCoveredDist = _coveredDist;
      _coveredDist = _distBtwn(_route.first, curLoc, 0, currLocInd);
      _currSegmInd = currLocInd;

      _prevSegmInd = currLocInd;
      _updateListOfPreviousLocations(curLoc);
      final bool flag = currLocInd < (_route.length - 1);
      _currRP = _route[currLocInd];
      _nextRP = flag ? _route[currLocInd + 1] : _route[currLocInd];
      _currRPInd = currLocInd;
      _nextRPInd = flag ? currLocInd + 1 : currLocInd;

      _updateIsJump(_coveredDist, _prevCoveredDist);
    }
  }

  List<LatLng> get route => _policy.route(_route);

  double get routeLength => _routeLen;

  double get coveredDistance => _coveredDist;

  bool get isFinished => _routeLen - _coveredDist <= _finishLineDist;

  LatLng get currentRoutePoint => _currRP;

  LatLng get nextRoutePoint => _nextRP;

  int get currentRoutePointIndex => _currRPInd;

  int get nextRoutePointIndex => _nextRPInd;

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
