import 'dart:collection';
import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'copy_policy.dart';
import 'geo_utils.dart';
import 'search_rect.dart';
import 'side_point.dart';

class RouteManagerBasic {
  RouteManagerBasic({
    required List<LatLng> route,
    double searchRectWidth = 10,
    double searchRectExtension = 5,
    double additionalChecksDist = 100,
    double maxVectDeviationInDeg = 45,
    double sameCordConst = 0.00001,
    double finishLineDist = 5,
    int lengthOfLists = 2,
    CopyPolicy? policy,
  }) {
    _route = checkForDuplications(route);
    _searchRectWidth = searchRectWidth;
    _searchRectExt = searchRectExtension;
    _additionalChecksDist = additionalChecksDist;
    _cos = cos(toRadians(maxVectDeviationInDeg));
    _sameCordConst = sameCordConst;
    _finishLineDist = finishLineDist;
    _lengthOfLists = lengthOfLists >= 1
        ? lengthOfLists
        : throw ArgumentError('Length of lists must be equal or more then 1');
    _policy = policy ?? CopyPolicy();

    if (_route.length < 2) {
      throw ArgumentError('Your route contains less than 2 points');
    } else {
      for (int i = 0; i < (_route.length - 1); i++) {
        _distFromStart[i] = _routeLen;
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
      // By default we think that we are starting at the beginning of the route
      _currRP = _route[0];
      _nextRP = _route[1];
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
  late final double _cos;
  late final double _additionalChecksDist;
  late final CopyPolicy _policy;
  late double _sameCordConst;

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

  /// A - start, B - end, aInd and bInd - A and B index on route
  double _distBtwn(LatLng A, LatLng B, int aInd, int bInd, {double dst = -1}) {
    final LatLng aOnRoute = _route[aInd];
    final LatLng bOnRoute = _route[bInd];

    final int ind = _distFromStart.length == bInd ? bInd - 1 : bInd;
    double dist = _distFromStart[ind]! - _distFromStart[aInd]!;
    if (dst >= 0) {
      dist += dst;
    } else {
      if (A != aOnRoute) dist += getDistance(p1: A, p2: aOnRoute);
      if (B != bOnRoute) dist += getDistance(p1: B, p2: bOnRoute);
    }
    return dist;
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
