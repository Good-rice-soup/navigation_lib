import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';
import 'search_rect.dart';
import 'side_point.dart';

/// The constructor takes two main parameters: path and sidePoints.
/// The latter can be optional (an empty array is passed in this case).
/// ``````
/// LaneWidth and laneExtension are dimensions in meters required for
/// the function to find the position of currentLocation on the path.
/// They affect the size of the rectangle constructed based on each
/// path segment. These values can be changed, but in general, they
/// are optimal.
/// ``````
/// finishLineDistance is the distance in meters to the end of the finish line.
/// If the remaining distance <= finishLineDistance, we can consider that we
/// have reached the end point.
/// ``````
/// LengthOfLists is the number of currentLocation values that the
/// object remembers (needed for smoother handling of turns, decoupling
/// angle calculations from the initial points of segments, etc.).
/// There should be at least one value to calculate the movement vector
/// (current location minus previous location).
class RouteManager {
  RouteManager({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
    required List<LatLng> wayPoints,
    double laneWidth = 10,
    double laneExtension = 5,
    double finishLineDistance = 5,
    int lengthOfLists = 2,
    double lengthToOutsidePoints = 100.0,
    int amountOfUpdatingSidePoints = 40,
    double additionalChecksDistance = 100,
    bool returnSPDataCopy = true,
    bool sortSPByDist = false,
    bool checkDuplications = true,
  }) {
    _route = checkDuplications ? checkRouteForDuplications(route) : route;
    _amountOfUpdatingSidePoints = amountOfUpdatingSidePoints;
    _laneExtension = laneExtension;
    _laneWidth = laneWidth;
    _finishLineDistance = finishLineDistance;
    _lengthOfLists = lengthOfLists >= 1
        ? lengthOfLists
        : throw ArgumentError('Length of lists must be equal or more then 1');
    _lengthToOutsidePoints = lengthToOutsidePoints;
    _additionalChecksDistance = additionalChecksDistance;

    _returnSPDataCopy = returnSPDataCopy;
    _sortSPByDist = sortSPByDist;

    if (_route.length < 2) {
      throw ArgumentError('Your route contains less than 2 points');
    } else {
      for (int i = 0; i < (_route.length - 1); i++) {
        _distFromStart[i] = _routeLength;
        final double distance = getDistance(p1: _route[i], p2: _route[i + 1]);
        _routeLength += distance;
        _segmentLengths[i] = distance;

        _maxSegmentLength =
            (distance > _maxSegmentLength) ? distance : _maxSegmentLength;

        _searchRectMap[i] = SearchRect(
          start: _route[i],
          end: _route[i + 1],
          rectWidth: _laneWidth,
          rectExt: _laneExtension,
        );
      }

      // By default we think that we are starting at the beginning of the route
      _nextRoutePoint = _route[1];

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

  static const String routeManagerVersion = '6.0.1';
  static const double sameCordConst = 0.0000005;

  List<LatLng> _route = [];
  double _routeLength = 0;
  late LatLng _nextRoutePoint;
  int _currentRoutePointIndex = 0;
  int _nextRoutePointIndex = 1;
  bool _isOnRoute = true;
  double _coveredDistance = 0;
  double _prevCoveredDistance = 0;
  int _currentSegmentIndex = 0;
  int _amountOfUpdatingSidePoints = 0;
  bool _isJump = false;

  late double _laneWidth;
  late double _laneExtension;
  late double _finishLineDistance;
  double _maxSegmentLength = 0;
  late double _lengthToOutsidePoints;
  late double _additionalChecksDistance;

  /// {segment index in the route, (lane rectangular, (velocity vector: x, y))}
  final Map<int, SearchRect> _searchRectMap = {};

  /// {segment index in the route, traveled distance form start}
  final Map<int, double> _distFromStart = {};

  /// {segment index in the route, segment length}
  final Map<int, double> _segmentLengths = {};

  /// {side point index in aligned side points, (closest way point index; right or left; past, next or onWay; distance from current location;)}
  /// ``````
  /// In function works with a beginning of segment.
  final Map<int, SidePoint> _alignedSP = {};

  /// [previous current location, previous previous current location, so on]
  /// ``````
  /// They are used for weighted vector sum.
  final List<LatLng> _listOfPreviousCurrentLocations = [];
  int _previousSegmentIndex = 0;
  final List<double> _listOfWeights = [];
  late int _lengthOfLists;

  /// exists to let position update at least 2 times (need to create vector)
  int _blocker = 2;

  // should return a copy or a pointer
  late final bool _returnSPDataCopy;
  late final bool _sortSPByDist;

  //-----------------------------Methods----------------------------------------

  /// Checks the path for duplicate coordinates, and returns the path without duplicates.
  static List<LatLng> checkRouteForDuplications(List<LatLng> route) {
    final List<LatLng> newRoute = [];
    int counter = 0;
    if (route.isNotEmpty) {
      newRoute.add(route[0]);
      for (int i = 1; i < route.length; i++) {
        if (route[i] != route[i - 1]) {
          newRoute.add(route[i]);
        } else {
          print(
              '[GeoUtils:RM]: Your route has a duplication of ${route[i]} (№${++counter}).');
        }
      }
    }
    print('[GeoUtils:RM]: Total amount of duplication $counter duplication');
    print('[GeoUtils:RM]:');
    return newRoute;
  }

  List<SidePoint> _indexingAndCutting(List<LatLng> sidePoints) {
    final List<SidePoint> indexedSidePoints = [];
    bool firstNextFlag = true;

    for (final LatLng sp in sidePoints) {
      // index of closes route point
      int ind = -1;
      double minDist = double.infinity;

      for (int routePInd = 0; routePInd < _route.length; routePInd++) {
        final dist = getDistance(p1: sp, p2: _route[routePInd]);
        if (dist <= _lengthToOutsidePoints && dist < minDist) {
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

        final PointState state = ind <= _currentRoutePointIndex
            ? PointState.past
            : firstNextFlag && ind > _currentRoutePointIndex
                ? (() {
                    firstNextFlag = false;
                    return PointState.next;
                  })()
                : PointState.onWay;

        _sortSPByDist
            ? indexedSidePoints.add(SidePoint(
                point: sp,
                routeInd: ind,
                position: position,
                state: state,
                dist: minDist))
            : indexedSidePoints.add(SidePoint(
                point: sp,
                routeInd: ind,
                position: position,
                state: state,
                dist: _distBetween(_route[_currentRoutePointIndex], sp,
                    _currentRoutePointIndex, ind)));
      }
    }
    return indexedSidePoints;
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
              final double dist = _distBetween(_route[_currentRoutePointIndex],
                  sp.point, _currentRoutePointIndex, sp.routeInd);

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
      _listOfPreviousCurrentLocations.add(_route[0]);
      _listOfWeights.add(1 / pow(2, i + 1));
    }
    _listOfWeights[0] += 1 / pow(2, _lengthOfLists);
  }

  void _updateListOfPreviousLocations(LatLng currentLocation) {
    final LatLng previousLocation = _listOfPreviousCurrentLocations.first;
    final double diffLat =
        (previousLocation.latitude - currentLocation.latitude).abs();
    final double diffLng =
        (previousLocation.longitude - currentLocation.longitude).abs();

    if (diffLat >= sameCordConst || diffLng >= sameCordConst) {
      for (int i = _listOfPreviousCurrentLocations.length - 1; i > 0; i--) {
        _listOfPreviousCurrentLocations[i] =
            _listOfPreviousCurrentLocations[i - 1];
      }
      _listOfPreviousCurrentLocations[0] = currentLocation;
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

  bool isPointOnRouteByLanes({required LatLng point}) {
    late bool isInRect;
    for (int i = 0; i < _searchRectMap.length; i++) {
      final SearchRect searchRect = _searchRectMap[i]!;
      isInRect = searchRect.isPointInRect(point);
      if (isInRect) {
        break;
      }
    }
    return isInRect;
  }

  (double, double) _calcWeightedVector(LatLng currentLocation) {
    (double, double) resultVector = (0, 0);
    for (int i = 0; i < _lengthOfLists; i++) {
      final LatLng previousLocation = _listOfPreviousCurrentLocations[i];
      final double coefficient = _listOfWeights[i];

      final (double, double) vector = (
        currentLocation.latitude - previousLocation.latitude,
        currentLocation.longitude - previousLocation.longitude
      );

      resultVector = (
        resultVector.$1 + coefficient * vector.$1,
        resultVector.$2 + coefficient * vector.$2
      );
    }
    return resultVector;
  }

  int _additionalChecks(
    LatLng currentLocation,
    int closestSegmentIndex,
    (double, double) motionVector,
  ) {
    final int length = _segmentLengths.length;
    int end = closestSegmentIndex;
    double distanceCheck = 0;
    for (int i = closestSegmentIndex; i < length - 1; i++) {
      if (distanceCheck >= _additionalChecksDistance) break;
      distanceCheck += _segmentLengths[i]!;
      end++;
    }

    int newClosestSegmentIndex = closestSegmentIndex;

    for (int i = closestSegmentIndex; i <= end; i++) {
      final SearchRect searchRect = _searchRectMap[i]!;
      final (double, double) segmentVector = searchRect.segmentVector;

      final double angle = getAngleBetweenVectors(motionVector, segmentVector);
      if (angle <= 46) {
        final bool isInLane = searchRect.isPointInRect(currentLocation);
        if (isInLane) {
          newClosestSegmentIndex = i;
        }
      }
    }
    return newClosestSegmentIndex;
  }

  /// Searches for the most farthest from the beginning of the path segment and
  /// returns its index, which coincides with the index of the starting point of
  /// the segment in the path.
  int _findClosestSegmentIndex(LatLng currentLocation) {
    int closestSegmentIndex = -1;
    final Iterable<int> segmentIndexesInRoute = _searchRectMap.keys;
    final (double, double) motionVector = _blocker > 0
        ? _searchRectMap[_previousSegmentIndex]!.segmentVector
        : _calcWeightedVector(currentLocation);

    bool isCurrentLocationFound = false;
    for (int i = _previousSegmentIndex; i < segmentIndexesInRoute.length; i++) {
      final SearchRect searchRect = _searchRectMap[i]!;
      final (double, double) segmentVector = searchRect.segmentVector;

      final double angle = getAngleBetweenVectors(motionVector, segmentVector);
      if (angle <= 46) {
        final bool isInLane = searchRect.isPointInRect(currentLocation);
        if (isInLane) {
          closestSegmentIndex = i;
          isCurrentLocationFound = true;
        }
      }
      if (isCurrentLocationFound) break;
    }

    if (!isCurrentLocationFound) {
      for (int i = 0; i < _previousSegmentIndex; i++) {
        final SearchRect searchRect = _searchRectMap[i]!;
        final (double, double) segmentVector = searchRect.segmentVector;

        final double angle =
            getAngleBetweenVectors(motionVector, segmentVector);
        if (angle <= 46) {
          final bool isInLane = searchRect.isPointInRect(currentLocation);
          if (isInLane) {
            closestSegmentIndex = i;
            isCurrentLocationFound = true;
          }
        }
        if (isCurrentLocationFound) break;
      }
    }
    _isOnRoute = isCurrentLocationFound;
    if (isCurrentLocationFound && _blocker <= 0) {
      closestSegmentIndex =
          _additionalChecks(currentLocation, closestSegmentIndex, motionVector);
    }
    return closestSegmentIndex;
  }

  Map<int, SidePoint> _deepCopySPData() {
    final Map<int, SidePoint> spCopy = {};
    final Iterable<int> keys = _alignedSP.keys;
    for (final int key in keys) {
      spCopy[key] = _alignedSP[key]!.copy();
    }
    return spCopy;
  }

  Map<int, SidePoint> updateStatesOfSidePoints(LatLng curLoc) {
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int currentLocationIndex = _findClosestSegmentIndex(curLoc);

    if (currentLocationIndex < 0 || currentLocationIndex >= _route.length) {
      print('[GeoUtils:RM]: You are not on the route.');
      return {};
    } else {
      _prevCoveredDistance = _coveredDistance;
      _coveredDistance =
          _distBetween(_route.first, curLoc, 0, currentLocationIndex);

      _currentSegmentIndex = currentLocationIndex;

      _previousSegmentIndex = currentLocationIndex;
      _updateListOfPreviousLocations(curLoc);
      _nextRoutePoint = (currentLocationIndex < (_route.length - 1))
          ? _route[currentLocationIndex + 1]
          : _route[currentLocationIndex];
      _nextRoutePointIndex = (currentLocationIndex < (_route.length - 1))
          ? currentLocationIndex + 1
          : currentLocationIndex;
      _currentRoutePointIndex = currentLocationIndex;

      final Iterable<int> sidePointIndexes = _alignedSP.keys;
      bool firstNextFlag = true;

      for (final int i in sidePointIndexes) {
        _alignedSP.update(i, (e) {
          final double distance =
              _distBetween(curLoc, e.point, currentLocationIndex, e.routeInd);

          final PointState state = e.routeInd <= currentLocationIndex
              ? PointState.past
              : firstNextFlag && e.routeInd > currentLocationIndex
                  ? (() {
                      firstNextFlag = false;
                      return PointState.next;
                    })()
                  : PointState.onWay;

          return e.update(newState: state, newDist: distance);
        });
      }
      return _returnSPDataCopy ? _deepCopySPData() : _alignedSP;
    }
  }

  Map<int, SidePoint> updateNStatesOfSidePoints(
    LatLng curLoc,
    int? curLocIndexOnRoute, {
    int amountSPToUpd = 40,
  }) {
    if (_amountOfUpdatingSidePoints < 0) {
      throw ArgumentError("amountOfUpdatingSidePoints can't be less then 0");
    }
    if (curLocIndexOnRoute != null &&
        (curLocIndexOnRoute < 0 || curLocIndexOnRoute >= _route.length)) {
      _isOnRoute = false;
      return {};
    }
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int currentLocationIndex;
    if (curLocIndexOnRoute != null) {
      currentLocationIndex = curLocIndexOnRoute;
      _isOnRoute = true;
    } else {
      currentLocationIndex = _findClosestSegmentIndex(curLoc);
    }

    if (currentLocationIndex < 0 || currentLocationIndex >= _route.length) {
      return {};
    } else {
      _prevCoveredDistance = _coveredDistance;
      _coveredDistance =
          _distBetween(_route.first, curLoc, 0, currentLocationIndex);
      _currentSegmentIndex = currentLocationIndex;

      _previousSegmentIndex = currentLocationIndex;
      _updateListOfPreviousLocations(curLoc);
      _nextRoutePoint = (currentLocationIndex < (_route.length - 1))
          ? _route[currentLocationIndex + 1]
          : _route[currentLocationIndex];
      _nextRoutePointIndex = (currentLocationIndex < (_route.length - 1))
          ? currentLocationIndex + 1
          : currentLocationIndex;
      _currentRoutePointIndex = currentLocationIndex;

      final Map<int, SidePoint> newSidePointsData = {};
      final Iterable<int> sidePointIndexes = _alignedSP.keys;
      bool firstNextFlag = true;
      int sidePointsAmountCounter = 0;

      for (final int i in sidePointIndexes) {
        if (sidePointsAmountCounter >= _amountOfUpdatingSidePoints) {
          break;
        }

        final SidePoint data = _alignedSP.update(i, (e) {
          if (e.state == PointState.past) {
            return e;
          }
          final double distance =
              _distBetween(curLoc, e.point, currentLocationIndex, e.routeInd);

          final PointState state = e.routeInd <= currentLocationIndex
              ? PointState.past
              : firstNextFlag && e.routeInd > currentLocationIndex
                  ? (() {
                      firstNextFlag = false;
                      return PointState.next;
                    })()
                  : PointState.onWay;

          return e.update(newState: state, newDist: distance);
        });

        if (data.state != PointState.past) {
          newSidePointsData[i] = data;
          sidePointsAmountCounter++;
        }
      }

      _updateIsJump(_coveredDistance, _prevCoveredDistance);
      return _returnSPDataCopy ? _deepCopySPData() : newSidePointsData;
    }
  }

  void updateCurrentLocation(LatLng curLoc) {
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int currentLocationIndex = _findClosestSegmentIndex(curLoc);

    if (currentLocationIndex < 0 || currentLocationIndex >= _route.length) {
      print('[GeoUtils:RM]: You are not on the route.');
    } else {
      print(
          '[GeoUtils:RM]: cd - $_coveredDistance : pcd - $_prevCoveredDistance');
      _prevCoveredDistance = _coveredDistance;

      _coveredDistance =
          _distBetween(_route.first, curLoc, 0, currentLocationIndex);
      _currentSegmentIndex = currentLocationIndex;

      _previousSegmentIndex = currentLocationIndex;
      _updateListOfPreviousLocations(curLoc);
      _nextRoutePoint = (currentLocationIndex < (_route.length - 1))
          ? _route[currentLocationIndex + 1]
          : _route[currentLocationIndex];
      _nextRoutePointIndex = (currentLocationIndex < (_route.length - 1))
          ? currentLocationIndex + 1
          : currentLocationIndex;
      _currentRoutePointIndex = currentLocationIndex;
    }
  }

  double get routeLength => _routeLength;

  LatLng get nextRoutePoint => _nextRoutePoint;

  int get nextRoutePointIndex => _nextRoutePointIndex;

  /// returns, are we still on route
  bool get isOnRoute {
    print('[GeoUtils:RM]: is: isOnRoute: $_isOnRoute');
    return _isOnRoute;
  }

  bool get isJump {
    if (_isJump) {
      _isJump = false;
      print('[GeoUtils:RM]: is: isJump: true');
      return true;
    }
    print('[GeoUtils:RM]: is: isJump: false');
    return false;
  }

  double get coveredDistance => _coveredDistance;

  bool get isFinished => _routeLength - _coveredDistance <= _finishLineDistance;

  int get currentSegmentIndex => _currentSegmentIndex;

  String get getVersion => routeManagerVersion;

  Map<int, SearchRect> get mapOfLanesData => _searchRectMap;

  Map<int, SidePoint> get sidePointsData =>
      _returnSPDataCopy ? _deepCopySPData() : _alignedSP;

  List<LatLng> get route => _route;
}
