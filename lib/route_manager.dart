import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'copy_policy.dart';
import 'geo_utils.dart';
import 'search_rect.dart';
import 'side_point.dart';

class RouteManager {
  RouteManager({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
    required List<LatLng> wayPoints,
    double searchRectWidth = 10,
    double searchRectExtension = 5,
    double finishLineDist = 5,
    int lengthOfLists = 2,
    double maxDistToSP = 100.0,
    int amountSPToUpd = 40,
    double additionalChecksDist = 100,
    CopyPolicy? policy,
    bool sortSPByDist = false,
    bool checkDuplications = true,
  }) {
    _route = checkDuplications ? checkForDuplications(route) : route;
    _amountSPToUpd = amountSPToUpd;
    _searchRectExt = searchRectExtension;
    _searchRectWidth = searchRectWidth;
    _finishLineDist = finishLineDist;
    _lengthOfLists = lengthOfLists >= 1
        ? lengthOfLists
        : throw ArgumentError('Length of lists must be equal or more then 1');
    _maxDistToSP = maxDistToSP;
    _additionalChecksDist = additionalChecksDist;

    _sortSPByDist = sortSPByDist;
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
      _nextRP = _route[1];

      if (sidePoints.isNotEmpty || wayPoints.isNotEmpty) {
        // TODO: check do we need to split way and side points - theoretically, we can, but we need to check that they go at the right order
        final List<SidePoint> indexedAndCuttedSP = [
          ..._indexingAndCutting(wayPoints),
          ..._indexingAndCutting(sidePoints)
        ];
        _aligning(indexedAndCuttedSP);
        _checkingPosition(indexedAndCuttedSP);
      }
      _generatePointsAndWeights();
    }
  }

  // naming:
  // RP - route point
  // SP - side point
  // SR - search rect

  static const String routeManagerVersion = '6.0.1';
  static const double sameCordConst = 0.0000005;

  late final List<LatLng> _route;
  double _routeLen = 0;
  late LatLng _nextRP;
  int _currentRPIndex = 0;
  int _nextRPInd = 1;
  bool _isOnRoute = true;
  double _coveredDist = 0;
  double _prevCoveredDist = 0;
  int _currSegmInd = 0;
  int _prevSegmInd = 0;
  int _amountSPToUpd = 0;
  bool _isJump = false;

  late final double _searchRectWidth;
  late final double _searchRectExt;
  late final double _finishLineDist;
  late final double _maxDistToSP;
  late final double _additionalChecksDist;

  /// {segment index in the route, search rect}
  final Map<int, SearchRect> _srMap = {};

  /// {segment index in the route, distance traveled form start}
  final Map<int, double> _distFromStart = {};

  /// {segment index in the route, segment length}
  final Map<int, double> _segmentsLen = {};

  /// {index of aligned side point, side point}
  /// ``````
  /// In function works with a beginning of segment.
  final Map<int, SidePoint> _alignedSP = {};

  /// [previous current location, previous previous current location, so on]
  /// ``````
  /// They are used for weighted vector sum.
  final List<LatLng> _listOfPrevCurrLoc = [];
  final List<double> _listOfWeights = [];
  late final int _lengthOfLists;

  /// exists to let position update at least 2 times (need to create vector)
  int _blocker = 2;

  late final bool _sortSPByDist;
  late final CopyPolicy _policy;

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

  List<SidePoint> _indexingAndCutting(List<LatLng> sidePoints) {
    final List<SidePoint> indexedSP = [];
    bool firstNextFlag = true;

    for (final LatLng sp in sidePoints) {
      // index of closes route point
      int ind = -1;
      double minDist = double.infinity;

      for (int routePInd = 0; routePInd < _route.length; routePInd++) {
        final dist = getDistance(p1: sp, p2: _route[routePInd]);
        if (dist <= _maxDistToSP && dist < minDist) {
          minDist = dist;
          ind = routePInd;
        }
      }

      if (ind != -1) {
        final bool isLast = ind < _route.length;
        final LatLng nextP = isLast ? _route[ind] : _route[ind + 1];
        final LatLng closestP = isLast ? _route[ind - 1] : _route[ind];

        final double skew = skewProduction(closestP, nextP, sp);
        final PointPosition position =
            skew <= 0 ? PointPosition.right : PointPosition.left;

        final PointState state = ind <= _currentRPIndex
            ? PointState.past
            : firstNextFlag && ind > _currentRPIndex
                ? (() {
                    firstNextFlag = false;
                    return PointState.next;
                  })()
                : PointState.onWay;

        _sortSPByDist
            ? indexedSP.add(SidePoint(
                point: sp,
                routeInd: ind,
                position: position,
                state: state,
                dist: minDist))
            : indexedSP.add(SidePoint(
                point: sp,
                routeInd: ind,
                position: position,
                state: state,
                dist: _distBetween(
                    _route[_currentRPIndex], sp, _currentRPIndex, ind)));
      }
    }
    return indexedSP;
  }

  void _aligning(List<SidePoint> indexedSidePoints) {
    _sortSPByDist
        ? indexedSidePoints.sort((a, b) {
            final indCompare = (a.routeInd == 0 ? -1 : a.routeInd)
                .compareTo(b.routeInd == 0 ? -1 : b.routeInd);

            if (indCompare != 0) return indCompare;
            return a.routeInd == 0
                ? -a.dist.compareTo(b.dist)
                : a.dist.compareTo(b.dist);
          })
        : indexedSidePoints.sort((a, b) => a.routeInd.compareTo(b.routeInd));
  }

  /// A - start, B - end
  double _distBetween(LatLng A, LatLng B, int aRouteInd, int bRouteInd) {
    final LatLng aOnRoute = _route[aRouteInd];
    final LatLng bOnRoute = _route[bRouteInd];

    double dist = _distFromStart[bRouteInd]! - _distFromStart[aRouteInd]!;
    if (A != aOnRoute) dist += getDistance(p1: A, p2: aOnRoute);
    if (B != bOnRoute) dist += getDistance(p1: B, p2: bOnRoute);
    return dist;
  }

  void _checkingPosition(
    List<SidePoint> alignedSPData,
  ) {
    int index = 0;

    _sortSPByDist
        ? (() {
            for (final SidePoint sp in alignedSPData) {
              final double dist = _distBetween(_route[_currentRPIndex],
                  sp.point, _currentRPIndex, sp.routeInd);

              _alignedSP[index] = sp.update(newState: sp.state, newDist: dist);
              index++;
            }
          })()
        : (() {
            for (final SidePoint sp in alignedSPData) {
              _alignedSP[index] = sp;
              index++;
            }
          })();
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

    if (diffLat >= sameCordConst || diffLng >= sameCordConst) {
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

  (double, double) _calcWeightedVector(LatLng currLoc) {
    (double, double) resultVector = (0, 0);
    for (int i = 0; i < _lengthOfLists; i++) {
      final LatLng prevLoc = _listOfPrevCurrLoc[i];
      final double coeff = _listOfWeights[i];

      final (double, double) vector = (
        currLoc.latitude - prevLoc.latitude,
        currLoc.longitude - prevLoc.longitude
      );

      resultVector = (
        resultVector.$1 + coeff * vector.$1,
        resultVector.$2 + coeff * vector.$2
      );
    }
    return resultVector;
  }

  int _additionalChecks(
      LatLng currLoc, int closestSegmInd, (double, double) motionVect) {
    final int length = _segmentsLen.length;
    int end = closestSegmInd;
    double distCheck = 0;
    for (int i = closestSegmInd; i < length - 1; i++) {
      if (distCheck >= _additionalChecksDist) break;
      distCheck += _segmentsLen[i]!;
      end++;
    }

    int newClosestSegmInd = closestSegmInd;

    for (int i = closestSegmInd; i <= end; i++) {
      final SearchRect searchRect = _srMap[i]!;
      final (double, double) segmentVector = searchRect.segmentVector;

      final double angle = getAngleBetweenVectors(motionVect, segmentVector);
      if (angle <= 46) {
        final bool isInLane = searchRect.isPointInRect(currLoc);
        if (isInLane) {
          newClosestSegmInd = i;
        }
      }
    }
    return newClosestSegmInd;
  }

  int _findClosestSegmentIndex(LatLng currLoc) {
    int closestSegmInd = -1;
    final Iterable<int> segmIndexes = _srMap.keys;
    final (double, double) motionVector = _blocker > 0
        ? _srMap[_prevSegmInd]!.segmentVector
        : _calcWeightedVector(currLoc);

    bool isCurrLocFound = false;
    for (int i = _prevSegmInd; i < segmIndexes.length; i++) {
      final SearchRect searchRect = _srMap[i]!;
      final (double, double) segmVect = searchRect.segmentVector;

      final double angle = getAngleBetweenVectors(motionVector, segmVect);
      if (angle <= 46) {
        final bool isInLane = searchRect.isPointInRect(currLoc);
        if (isInLane) {
          closestSegmInd = i;
          isCurrLocFound = true;
        }
      }
      if (isCurrLocFound) break;
    }

    if (!isCurrLocFound) {
      for (int i = 0; i < _prevSegmInd; i++) {
        final SearchRect searchRect = _srMap[i]!;
        final (double, double) segmVect = searchRect.segmentVector;

        final double angle = getAngleBetweenVectors(motionVector, segmVect);
        if (angle <= 46) {
          final bool isInLane = searchRect.isPointInRect(currLoc);
          if (isInLane) {
            closestSegmInd = i;
            isCurrLocFound = true;
          }
        }
        if (isCurrLocFound) break;
      }
    }

    _isOnRoute = isCurrLocFound;
    if (isCurrLocFound && _blocker <= 0) {
      closestSegmInd = _additionalChecks(currLoc, closestSegmInd, motionVector);
    }
    return closestSegmInd;
  }

  Map<int, SidePoint> updateSidePoints(LatLng currLoc, int? currLocInd) {
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
      _coveredDist = _distBetween(_route.first, currLoc, 0, curLocInd);
      _currSegmInd = curLocInd;

      _prevSegmInd = curLocInd;
      _updateListOfPreviousLocations(currLoc);
      final bool flag = curLocInd < (_route.length - 1);
      _nextRP = flag ? _route[curLocInd + 1] : _route[curLocInd];
      _nextRPInd = flag ? curLocInd + 1 : curLocInd;
      _currentRPIndex = curLocInd;

      bool firstNextFlag = true;
      for (final int i in _alignedSP.keys) {
        _alignedSP.update(i, (e) {
          final double dist =
              _distBetween(currLoc, e.point, curLocInd, e.routeInd);

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

  Map<int, SidePoint> updateNSidePoints(
    LatLng currLoc,
    int? currLocInd, {
    int amountSPToUpd = 40,
  }) {
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
      _coveredDist = _distBetween(_route.first, currLoc, 0, curLocInd);
      _currSegmInd = curLocInd;

      _prevSegmInd = curLocInd;
      _updateListOfPreviousLocations(currLoc);
      final bool flag = curLocInd < (_route.length - 1);
      _nextRP = flag ? _route[curLocInd + 1] : _route[curLocInd];
      _nextRPInd = flag ? curLocInd + 1 : curLocInd;
      _currentRPIndex = curLocInd;

      final Map<int, SidePoint> newSPData = {};
      bool firstNextFlag = true;
      int spAmount = 0;

      for (final int i in _alignedSP.keys) {
        if (spAmount >= _amountSPToUpd) break;

        final SidePoint data = _alignedSP.update(i, (e) {
          if (e.state == PointState.past) return e;
          final double dist =
              _distBetween(currLoc, e.point, curLocInd, e.routeInd);

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

  void updateCurrentLocation(LatLng curLoc, int? curLocInd) {
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
      _coveredDist = _distBetween(_route.first, curLoc, 0, currLocInd);
      _currSegmInd = currLocInd;

      _prevSegmInd = currLocInd;
      _updateListOfPreviousLocations(curLoc);
      final bool flag = currLocInd < (_route.length - 1);
      _nextRP = flag ? _route[currLocInd + 1] : _route[currLocInd];
      _nextRPInd = flag ? currLocInd + 1 : currLocInd;
      _currentRPIndex = currLocInd;

      _updateIsJump(_coveredDist, _prevCoveredDist);
    }
  }

  double get routeLength => _routeLen;

  LatLng get nextRoutePoint => _nextRP;

  int get nextRoutePointIndex => _nextRPInd;

  bool get isOnRoute => _isOnRoute;

  bool get isJump {
    if (_isJump) {
      _isJump = false;
      return true;
    }
    return false;
  }

  double get coveredDistance => _coveredDist;

  bool get isFinished => _routeLen - _coveredDist <= _finishLineDist;

  int get currentSegmentIndex => _currSegmInd;

  String get getVersion => routeManagerVersion;

  Map<int, SearchRect> get searchRectMap => _policy.searchRect(_srMap);

  Map<int, SidePoint> get sidePointsData => _policy.sidePoints(_alignedSP);

  List<LatLng> get route => _policy.route(_route);
}
