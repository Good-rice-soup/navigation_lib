import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';
import 'search_rect.dart';

//TODO: спросить про необходимость сортировки по расстоянию после сортировки по индексу

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
  }) {
    _route = checkRouteForDuplications(route);
    _amountOfUpdatingSidePoints = amountOfUpdatingSidePoints;
    _laneExtension = laneExtension;
    _laneWidth = laneWidth;
    _finishLineDistance = finishLineDistance;
    _lengthOfLists = lengthOfLists >= 1
        ? lengthOfLists
        : throw ArgumentError('Length of lists must be equal or more then 1');
    _lengthToOutsidePoints = lengthToOutsidePoints;
    _additionalChecksDistance = additionalChecksDistance;

    if (_route.length < 2) {
      throw ArgumentError('Your route contains less than 2 points');
    } else {
      for (int i = 0; i < (_route.length - 1); i++) {
        _distanceFromStart[i] = _routeLength;
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
      _nextRoutePointIndex = 1;

      if (sidePoints.isNotEmpty || wayPoints.isNotEmpty) {
        final List<({int ind, LatLng p, double dist})> indexedAndCuttedSP = [
          ..._indexingAndCutting(_route, wayPoints),
          ..._indexingAndCutting(_route, sidePoints)
        ];
        _aligning(indexedAndCuttedSP);
        _checkingPosition(_route, indexedAndCuttedSP);
      }
      _generatePointsAndWeights();
    }
  }

  static const String routeManagerVersion = '6.0.1';
  static const double sameCordConst = 0.0000005;

  List<LatLng> _route = [];
  double _routeLength = 0;
  late LatLng _nextRoutePoint;
  late int _nextRoutePointIndex;
  bool _isOnRoute = true;
  final List<LatLng> _alignedSidePoints = [];
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
  final Map<int, double> _distanceFromStart = {};

  /// {segment index in the route, segment length}
  final Map<int, double> _segmentLengths = {};

  //TODO: check is data needed
  /// [(side point index in aligned side points; right or left; past, next or onWay; distance from current location;)]
  List<({int alignedSPInd, String position, String stateOnRoute, double dist})>
      _sidePointsData = [];

  /// {side point index in aligned side points, (closest way point index; right or left; past, next or onWay; distance from current location;)}
  /// ``````
  /// In function works with a beginning of segment.
  final Map<int,
          ({int wpInd, String position, String stateOnRoute, double dist})>
      _sidePointsStatesHashTable = {};

  /// [previous current location, previous previous current location, so on]
  /// ``````
  /// They are used for weighted vector sum.
  final List<LatLng> _listOfPreviousCurrentLocations = [];
  int _previousSegmentIndex = 0;
  final List<double> _listOfWeights = [];
  late int _lengthOfLists;

  /// если при старте движения наша текуща позиция обновилась менее двух раз, мы почти гарантированно получим сход с пути и его перестройку
  int _blocker = 2;

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

  List<({int ind, LatLng p, double dist})> _indexingAndCutting(
    List<LatLng> route,
    List<LatLng> sidePoints,
  ) {
    final List<({int ind, LatLng p, double dist})> indexedSidePoints = [];

    for (final LatLng sp in sidePoints) {
      int closestInd = -1;
      double minDist = double.infinity;

      for (int routePInd = 0; routePInd < route.length; routePInd++) {
        final dist = getDistance(p1: sp, p2: route[routePInd]);
        if (dist <= _lengthToOutsidePoints && dist < minDist) {
          minDist = dist;
          closestInd = routePInd;
        }
      }

      if (closestInd != -1) {
        indexedSidePoints.add((ind: closestInd, p: sp, dist: minDist));
      }
    }
    return indexedSidePoints;
  }

  void _aligning(List<({int ind, LatLng p, double dist})> indexedSidePoints) {
    indexedSidePoints.sort((a, b) {
      final indCompare =
          (a.ind == 0 ? -1 : a.ind).compareTo(b.ind == 0 ? -1 : b.ind);
      if (indCompare != 0) return indCompare;
      return a.ind == 0 ? -a.dist.compareTo(b.dist) : a.dist.compareTo(b.dist);
    });

    _alignedSidePoints.addAll(indexedSidePoints.map((e) => e.p));
  }

  void _checkingPosition(
    List<LatLng> route,
    List<({int ind, LatLng p, double dist})> alignedSPData,
  ) {
    const startIndex = 0;
    bool firstNextFlag = true;
    int index = 0;

    for (final ({int ind, LatLng p, double dist}) data in alignedSPData) {
      final bool isLast = data.ind == route.length - 1;

      final LatLng nextP = isLast ? route[data.ind] : route[data.ind + 1];

      final LatLng closestP = isLast ? route[data.ind - 1] : route[data.ind];

      final double skew = skewProduction(closestP, nextP, data.p);
      final String position = skew <= 0 ? 'right' : 'left';

      final double distance = getDistanceFromAToB(
        _route[startIndex],
        data.p,
        aSegmentIndex: startIndex,
        bSegmentIndex: data.ind,
      ).$1;

      final String state = data.ind <= startIndex
          ? 'past'
          : firstNextFlag && data.ind > startIndex
              ? (() {
                  firstNextFlag = false;
                  return 'next';
                })()
              : 'onWay';

      _sidePointsData.add((
        alignedSPInd: index,
        position: position,
        stateOnRoute: state,
        dist: distance
      ));

      _sidePointsStatesHashTable[index] = (
        wpInd: data.ind,
        position: position,
        stateOnRoute: state,
        dist: distance
      );
      index++;
    }
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

  static double getAngleBetweenVectors(
      (double, double) v1, (double, double) v2) {
    final double dotProduct = v1.$1 * v2.$1 + v1.$2 * v2.$2;
    final double v1Length = sqrt(v1.$1 * v1.$1 + v1.$2 * v1.$2);
    final double v2Length = sqrt(v2.$1 * v2.$1 + v2.$2 * v2.$2);
    final double angle =
        toDegrees(acos((dotProduct / (v1Length * v2Length)).clamp(-1, 1)));
    return angle;
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

  //constructor
  @Deprecated('Use [isPointOnRouteByLanes]')
  bool isPointOnRouteByRadius({required LatLng point, required double radius}) {
    if (radius.isNaN || radius.isNegative) {
      throw ArgumentError("Variable radius can't be NaN or negative");
    }

    double minDistance = double.infinity;
    for (final LatLng routePoint in _route) {
      final double distance = getDistance(p1: point, p2: routePoint);
      if (distance < minDistance) {
        minDistance = distance;
        if (minDistance < radius) {
          return true;
        }
      }
    }
    return false;
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

  /// [(side point index in aligned side points; right or left; past, next or onWay)]
  /// ``````
  /// Updates side points' states by current location.
  List<({int alignedSPInd, String position, String stateOnRoute, double dist})>
      updateStatesOfSidePoints(LatLng currentLocation) {
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int currentLocationIndex = _findClosestSegmentIndex(currentLocation);

    if (currentLocationIndex < 0 || currentLocationIndex >= _route.length) {
      print('[GeoUtils:RM]: You are not on the route.');
      return [];
    } else {
      _prevCoveredDistance = _coveredDistance;
      final double newDist = _distanceFromStart[currentLocationIndex]!;
      _coveredDistance = newDist +
          getDistance(p1: currentLocation, p2: _route[currentLocationIndex]);

      _currentSegmentIndex = currentLocationIndex;

      _previousSegmentIndex = currentLocationIndex;
      _updateListOfPreviousLocations(currentLocation);
      _nextRoutePoint = (currentLocationIndex < (_route.length - 1))
          ? _route[currentLocationIndex + 1]
          : _route[currentLocationIndex];
      _nextRoutePointIndex = (currentLocationIndex < (_route.length - 1))
          ? currentLocationIndex + 1
          : currentLocationIndex;

      final List<
          ({
            int alignedSPInd,
            String position,
            String stateOnRoute,
            double dist
          })> newSidePointsData = [];
      final Iterable<int> sidePointIndexes = _sidePointsStatesHashTable.keys;
      bool firstNextFlag = true;

      for (final int i in sidePointIndexes) {
        final ({
          int wpInd,
          String position,
          String stateOnRoute,
          double dist
        }) data = _sidePointsStatesHashTable.update(i, (value) {
          if (value.wpInd <= currentLocationIndex) {
            final double distance = getDistanceFromAToB(
                    currentLocation, _alignedSidePoints[i],
                    aSegmentIndex: currentLocationIndex,
                    bSegmentIndex: value.wpInd)
                .$1;
            return (
              wpInd: value.wpInd,
              position: value.position,
              stateOnRoute: 'past',
              dist: distance
            );
          } else if (firstNextFlag && (value.wpInd > currentLocationIndex)) {
            firstNextFlag = false;
            final double distance = getDistanceFromAToB(
                    currentLocation, _alignedSidePoints[i],
                    aSegmentIndex: currentLocationIndex,
                    bSegmentIndex: value.wpInd)
                .$1;
            return (
              wpInd: value.wpInd,
              position: value.position,
              stateOnRoute: 'next',
              dist: distance
            );
          } else {
            final double distance = getDistanceFromAToB(
                    currentLocation, _alignedSidePoints[i],
                    aSegmentIndex: currentLocationIndex,
                    bSegmentIndex: value.wpInd)
                .$1;
            return (
              wpInd: value.wpInd,
              position: value.position,
              stateOnRoute: 'onWay',
              dist: distance
            );
          }
        });

        newSidePointsData.add((
          alignedSPInd: i,
          position: data.position,
          stateOnRoute: data.stateOnRoute,
          dist: data.dist
        ));
      }

      _sidePointsData = newSidePointsData;
      return newSidePointsData;
    }
  }

  List<({int alignedSPInd, String position, String stateOnRoute, double dist})>
      updateNStatesOfSidePoints(
    LatLng currentLocation,
    int? currentLocationIndexOnRoute, {
    int amountOfUpdatingSidePoints = 40,
  }) {
    if (_amountOfUpdatingSidePoints < 0) {
      throw ArgumentError("amountOfUpdatingSidePoints can't be less then 0");
    }
    if (currentLocationIndexOnRoute != null &&
        (currentLocationIndexOnRoute < 0 ||
            currentLocationIndexOnRoute >= _route.length)) {
      _isOnRoute = false;
      return [];
    }
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int currentLocationIndex;
    if (currentLocationIndexOnRoute != null) {
      currentLocationIndex = currentLocationIndexOnRoute;
      _isOnRoute = true;
    } else {
      currentLocationIndex = _findClosestSegmentIndex(currentLocation);
    }

    if (currentLocationIndex < 0 || currentLocationIndex >= _route.length) {
      return [];
    } else {
      _prevCoveredDistance = _coveredDistance;
      final double newDist = _distanceFromStart[currentLocationIndex]!;
      _coveredDistance = newDist +
          getDistance(p1: currentLocation, p2: _route[currentLocationIndex]);
      _currentSegmentIndex = currentLocationIndex;

      _previousSegmentIndex = currentLocationIndex;
      _updateListOfPreviousLocations(currentLocation);
      _nextRoutePoint = (currentLocationIndex < (_route.length - 1))
          ? _route[currentLocationIndex + 1]
          : _route[currentLocationIndex];
      _nextRoutePointIndex = (currentLocationIndex < (_route.length - 1))
          ? currentLocationIndex + 1
          : currentLocationIndex;

      final List<
          ({
            int alignedSPInd,
            String position,
            String stateOnRoute,
            double dist
          })> newSidePointsData = [];
      final Iterable<int> sidePointIndexes = _sidePointsStatesHashTable.keys;
      bool firstNextFlag = true;
      int sidePointsAmountCounter = 0;

      for (final int i in sidePointIndexes) {
        if (sidePointsAmountCounter >= _amountOfUpdatingSidePoints) {
          break;
        }

        final ({
          int wpInd,
          String position,
          String stateOnRoute,
          double dist
        }) data = _sidePointsStatesHashTable.update(i, (value) {
          if (value.stateOnRoute == 'past') {
            return value;
          }
          if (value.wpInd <= currentLocationIndex) {
            final double distance = getDistanceFromAToB(
                    currentLocation, _alignedSidePoints[i],
                    aSegmentIndex: currentLocationIndex,
                    bSegmentIndex: value.wpInd)
                .$1;
            return (
              wpInd: value.wpInd,
              position: value.position,
              stateOnRoute: 'past',
              dist: distance
            );
          } else if (firstNextFlag && (value.wpInd > currentLocationIndex)) {
            firstNextFlag = false;
            final double distance = getDistanceFromAToB(
                    currentLocation, _alignedSidePoints[i],
                    aSegmentIndex: currentLocationIndex,
                    bSegmentIndex: value.wpInd)
                .$1;
            return (
              wpInd: value.wpInd,
              position: value.position,
              stateOnRoute: 'next',
              dist: distance
            );
          } else {
            final double distance = getDistanceFromAToB(
                    currentLocation, _alignedSidePoints[i],
                    aSegmentIndex: currentLocationIndex,
                    bSegmentIndex: value.wpInd)
                .$1;
            return (
              wpInd: value.wpInd,
              position: value.position,
              stateOnRoute: 'onWay',
              dist: distance
            );
          }
        });
        if (data.stateOnRoute != 'past') {
          newSidePointsData.add((
            alignedSPInd: i,
            position: data.position,
            stateOnRoute: data.stateOnRoute,
            dist: data.dist
          ));
          sidePointsAmountCounter++;
        }
      }

      _updateIsJump(_coveredDistance, _prevCoveredDistance);
      _sidePointsData = newSidePointsData;
      return newSidePointsData;
    }
  }

  void updateCurrentLocation(LatLng currentLocation) {
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int currentLocationIndex = _findClosestSegmentIndex(currentLocation);

    if (currentLocationIndex < 0 || currentLocationIndex >= _route.length) {
      print('[GeoUtils:RM]: You are not on the route.');
    } else {
      /*
      _coveredDistance +=
          getDistance(currentLocation, _listOfPreviousCurrentLocations[0]);
       */
      print(
          '[GeoUtils:RM]: cd - $_coveredDistance : pcd - $_prevCoveredDistance');
      _prevCoveredDistance = _coveredDistance;

      final double newDist = _distanceFromStart[currentLocationIndex]!;
      _coveredDistance = newDist +
          getDistance(p1: currentLocation, p2: _route[currentLocationIndex]);
      _currentSegmentIndex = currentLocationIndex;

      _previousSegmentIndex = currentLocationIndex;
      _updateListOfPreviousLocations(currentLocation);
      _nextRoutePoint = (currentLocationIndex < (_route.length - 1))
          ? _route[currentLocationIndex + 1]
          : _route[currentLocationIndex];
      _nextRoutePointIndex = (currentLocationIndex < (_route.length - 1))
          ? currentLocationIndex + 1
          : currentLocationIndex;
    }
  }

  /// Primitive search by distance.
  int _primitiveFindClosestSegmentIndex(LatLng point) {
    // Searching by segments first point.
    final double radius = _maxSegmentLength + 1;
    double distance = double.infinity;
    int closestRouteIndex = -1;

    for (int i = 0; i < (_route.length - 1); i++) {
      final double newDistance = getDistance(p1: point, p2: _route[i]);

      if ((newDistance < distance) && (newDistance < radius)) {
        closestRouteIndex = i;
        distance = newDistance;
      }
    }
    return closestRouteIndex;
  }

  /// (distance from A to B; index of segment where A located; index of segment where B located)
  (double, int, int) getDistanceFromAToB(
    LatLng A,
    LatLng B, {
    int aSegmentIndex = -1,
    int bSegmentIndex = -1,
  }) {
    LatLng a = A;
    LatLng b = B;
    int startSegmentIndex = aSegmentIndex == -1
        ? _primitiveFindClosestSegmentIndex(a)
        : aSegmentIndex;
    int endSegmentIndex = bSegmentIndex == -1
        ? _primitiveFindClosestSegmentIndex(b)
        : bSegmentIndex;

    // final bool indentFlag = endSegmentIndex == _route.length - 1;

    if (startSegmentIndex == -1 || endSegmentIndex == -1) {
      print("[GeoUtils:RM]: A, B or both doesn't lying on the route.");
      return (0, startSegmentIndex, endSegmentIndex);
    }

    (startSegmentIndex, endSegmentIndex, a, b) =
        (startSegmentIndex > endSegmentIndex)
            ? (endSegmentIndex, startSegmentIndex, b, a)
            : (startSegmentIndex, endSegmentIndex, a, b);

    final LatLng nearestToStartSegmentPoint = _route[startSegmentIndex + 1];
    // final LatLng nearestToEndSegmentPoint = _route[endSegmentIndex];
    double firstDistance = getDistance(p1: a, p2: nearestToStartSegmentPoint);
    // double secondDistance = getDistance(nearestToEndSegmentPoint, b);

    final (double, double) vector1 = (
      nearestToStartSegmentPoint.latitude - a.latitude,
      nearestToStartSegmentPoint.longitude - a.longitude
    );
    final (double, double) vector2 =
        _searchRectMap[startSegmentIndex]!.segmentVector;
    final double angle = getAngleBetweenVectors(vector1, vector2);
    firstDistance = angle < 90 ? firstDistance : -firstDistance;

    // final (double, double) vector3 = (
    //   b.latitude - nearestToEndSegmentPoint.latitude,
    //   b.longitude - nearestToEndSegmentPoint.longitude
    // );
    // final (double, double) vector4 = !indentFlag
    //     ? _mapOfLanesData[endSegmentIndex]!.$2
    //     : _mapOfLanesData[endSegmentIndex - 1]!.$2;
    // angle = getAngleBetweenVectors(vector3, vector4);
    // secondDistance = angle < 90 ? secondDistance : -secondDistance;

    double distance = 0;
    for (int i = startSegmentIndex + 1; i < endSegmentIndex; i++) {
      distance += _segmentLengths[i]!;
    }
    distance += firstDistance; // + secondDistance

    return (distance, startSegmentIndex, endSegmentIndex);
  }

  /// (covered distance, are we at finish line, segment index where current point is located)
  (double, bool, int) getCoveredDistance(LatLng location) {
    final (coveredDistance, _, locationSegmentIndex) =
        getDistanceFromAToB(_route[0], location, aSegmentIndex: 0);

    final bool isFinished =
        (_routeLength - coveredDistance) < _finishLineDistance;

    return (coveredDistance, isFinished, locationSegmentIndex);
  }

  void deleteSidePoint(LatLng point) {
    final int index = _alignedSidePoints.indexOf(point);
    _sidePointsStatesHashTable.remove(index);
    //_sidePointsData.remove(_sidePointsData.firstWhere((e) => e.$1 == index));
    _alignedSidePoints.remove(point);
  }

  void _updateIsJump(double currentDist, double previousDist) {
    if (_isJump == true) return;
    _isJump = currentDist - previousDist > 100 ? true : false;
  }

  List<LatLng> get alignedSidePoints => _alignedSidePoints;

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

  /// Returns a list [(side point index in aligned side points; right or left; past, next or onWay)].
  List<({int alignedSPInd, String position, String stateOnRoute, double dist})>
      get sidePointsData => _sidePointsData;

  /// Returns a map {segment index in the route, (lane rectangular, (velocity vector: x, y))}.
  Map<int, SearchRect> get mapOfLanesData => _searchRectMap;

  Map<int, ({int wpInd, String position, String stateOnRoute, double dist})>
      get sidePointsStatesHashTable => _sidePointsStatesHashTable;

  List<LatLng> get route => _route;
}
