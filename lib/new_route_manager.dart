import 'dart:math' as math;

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

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
class NewRouteManager {
  NewRouteManager({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
    double laneWidth = 10,
    double laneExtension = 5,
    double finishLineDistance = 5,
    int lengthOfLists = 2,
    double lengthToOutsidePoints = 100.0,
    int amountOfUpdatingSidePoints = 40,
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

    if (_route.isEmpty) {
      _alignedSidePoints = sidePoints;
    } else if (_route.length == 1) {
      _aligning(_route, sidePoints);
    } else {
      for (int i = 0; i < (_route.length - 1); i++) {
        _distanceFromStart[i] = _routeLength;
        final double distance = getDistance(_route[i], _route[i + 1]);
        _routeLength += distance;
        _segmentLengths[i] = distance;

        _maxSegmentLength =
            (distance > _maxSegmentLength) ? distance : _maxSegmentLength;

        _mapOfLanesData[i] = (
          _createLane(_route[i], _route[i + 1]),
          (
            _route[i + 1].latitude - _route[i].latitude,
            _route[i + 1].longitude - _route[i].longitude
          ),
        );
      }

      // By default we think that we are starting at the beginning of the route
      _nextRoutePoint = _route[1];
      _nextRoutePointIndex = 1;

      if (sidePoints.isNotEmpty) {
        // _aligning() called as a position arg before _alignedSidePoints cause it updates _alignedSidePoints
        _checkingPosition(
            _route, _aligning(_route, sidePoints), _alignedSidePoints);
      }
      _generatePointsAndWeights();
    }
  }

  static const String routeManagerVersion = 'v5';
  static const double earthRadiusInMeters = 6371009.0;
  static const double metersPerDegree = 111195.0797343687;

  List<LatLng> _route = [];
  double _routeLength = 0;
  late LatLng _nextRoutePoint;
  late int _nextRoutePointIndex;
  bool _isOnRoute = true;
  List<LatLng> _alignedSidePoints = [];
  double _coveredDistance = 0;
  int _currentSegmentIndex = 0;
  int _amountOfUpdatingSidePoints = 0;

  late double _laneWidth;
  late double _laneExtension;
  late double _finishLineDistance;
  double _maxSegmentLength = 0;
  late double _lengthToOutsidePoints;

  /// {segment index in the route, (lane rectangular, (velocity vector: x, y))}
  final Map<int, (List<LatLng>, (double, double))> _mapOfLanesData = {};

  /// {segment index in the route, traveled distance form start}
  final Map<int, double> _distanceFromStart = {};

  /// {segment index in the route, segment length}
  final Map<int, double> _segmentLengths = {};

  /// [(side point index in aligned side points; right or left; past, next or onWay; distance from current location;)]
  List<(int, String, String, double)> _sidePointsData = [];

  /// {side point index in aligned side points, (closest way point index; right or left; past, next or onWay; distance from current location;)}
  /// ``````
  /// In function works with a beginning of segment.
  final Map<int, (int, String, String, double)> _sidePointsStatesHashTable = {};

  /// [previous current location, previous previous current location, so on]
  /// ``````
  /// They are used for weighted vector sum.
  final List<LatLng> _listOfPreviousCurrentLocations = [];
  int _previousSegmentIndex = 0;
  final List<double> _listOfWeights = [];
  late int _lengthOfLists;

  final List<void Function()> _listeners = [];

  //-----------------------------Methods----------------------------------------

  /// Checks the path for duplicate coordinates, and returns the path without duplicates.
  static List<LatLng> checkRouteForDuplications(List<LatLng> route) {
    final List<LatLng> newRoute = [];
    for (int i = 0; i < (route.length - 1); i++) {
      route[i] == route[i + 1]
          ? print('[GeoUtils]: Your route have a duplication of ${route[i]}.')
          : newRoute.add(route[i]);
    }
    if (route[route.length - 1] != route[route.length - 2]) {
      newRoute.add(route[route.length - 1]);
    }
    return newRoute;
  }

  /// Get distance between two points.
  static double getDistance(LatLng point1, LatLng point2) {
    final double deltaLat = toRadians(point2.latitude - point1.latitude);
    final double deltaLon = toRadians(point2.longitude - point1.longitude);

    final double haversinLat = math.pow(math.sin(deltaLat / 2), 2).toDouble();
    final double haversinLon = math.pow(math.sin(deltaLon / 2), 2).toDouble();
    final double parameter = math.cos(toRadians(point1.latitude)) *
        math.cos(toRadians(point2.latitude));
    final double asinArgument =
        math.sqrt(haversinLat + haversinLon * parameter).clamp(-1, 1);

    return earthRadiusInMeters * 2 * math.asin(asinArgument);
  }

  /// Degrees to radians.
  static double toRadians(double deg) {
    return deg * (math.pi / 180);
  }

  /// Radians to degrees.
  static double toDegrees(double rad) {
    return rad * (180 / math.pi);
  }

  List<LatLng> _createLane(LatLng start, LatLng end) {
    final double deltaLng = end.longitude - start.longitude;
    final double deltaLat = end.latitude - start.latitude;
    final double length = math.sqrt(deltaLng * deltaLng + deltaLat * deltaLat);

    // Converting lane width to degrees
    final double lngNormal = -(deltaLat / length) *
        metersToLongitudeDegrees(_laneWidth, start.latitude);
    final double latNormal =
        (deltaLng / length) * metersToLatitudeDegrees(_laneWidth);

    // Converting lane extension to degrees
    final LatLng extendedStart = LatLng(
        start.latitude -
            (deltaLat / length) * metersToLatitudeDegrees(_laneExtension),
        start.longitude -
            (deltaLng / length) *
                metersToLongitudeDegrees(_laneExtension, start.latitude));
    final LatLng extendedEnd = LatLng(
        end.latitude +
            (deltaLat / length) * metersToLatitudeDegrees(_laneExtension),
        end.longitude +
            (deltaLng / length) *
                metersToLongitudeDegrees(_laneExtension, end.latitude));

    return [
      LatLng(
          extendedEnd.latitude + latNormal, extendedEnd.longitude + lngNormal),
      LatLng(
          extendedEnd.latitude - latNormal, extendedEnd.longitude - lngNormal),
      LatLng(extendedStart.latitude - latNormal,
          extendedStart.longitude - lngNormal),
      LatLng(extendedStart.latitude + latNormal,
          extendedStart.longitude + lngNormal),
    ];
  }

  /// Convert meters to latitude degrees.
  static double metersToLatitudeDegrees(double meters) {
    return meters / metersPerDegree;
  }

  /// Convert meters to longitude degrees using latitude.
  static double metersToLongitudeDegrees(double meters, double latitude) {
    return meters / (metersPerDegree * math.cos(toRadians(latitude)));
  }

  List<(int, LatLng, double)> _aligning(
      List<LatLng> route, List<LatLng> sidePoints) {
    // (wayPointIndex, sidePoint, distanceBetween, shouldRemove)
    final List<(int, LatLng, double, bool)> preIndexedSidePoints = [];
    for (final LatLng sidePoint in sidePoints) {
      preIndexedSidePoints.add((0, sidePoint, double.infinity, false));
    }

    for (int wayPointIndex = 0; wayPointIndex < route.length; wayPointIndex++) {
      for (int i = 0; i < sidePoints.length; i++) {
        final (int, LatLng, double, bool) data = preIndexedSidePoints[i];
        final double distance = getDistance(data.$2, route[wayPointIndex]);
        if (distance < data.$3) {
          preIndexedSidePoints[i] = (
            wayPointIndex,
            data.$2,
            distance,
            distance > _lengthToOutsidePoints
          );
        }
      }
    }

    // (wayPointIndex, sidePoint, distanceBetween)
    final List<(int, LatLng, double)> indexedSidePoints = [];

    for (final (int, LatLng, double, bool) data in preIndexedSidePoints) {
      if (data.$4 == false) {
        indexedSidePoints.add((data.$1, data.$2, data.$3));
      }
    }

    final List<(int, LatLng, double)> zeroIndexedSidePoints = [];
    final List<(int, LatLng, double)> otherIndexedSidePoints = [];
    for (final (int, LatLng, double) data in indexedSidePoints) {
      data.$1 == 0
          ? zeroIndexedSidePoints.add(data)
          : otherIndexedSidePoints.add(data);
    }

    zeroIndexedSidePoints.sort((a, b) => a.$1.compareTo(b.$1) != 0
        ? a.$1.compareTo(b.$1)
        : -1 * a.$3.compareTo(b.$3));

    otherIndexedSidePoints.sort((a, b) => a.$1.compareTo(b.$1) != 0
        ? a.$1.compareTo(b.$1)
        : a.$3.compareTo(b.$3));

    final List<LatLng> alignedSidePoints = [];
    final List<(int, LatLng, double)> alignedSidePointsData = [];

    for (final (int, LatLng, double) data in zeroIndexedSidePoints) {
      alignedSidePoints.add(data.$2);
      alignedSidePointsData.add(data);
    }

    for (final (int, LatLng, double) data in otherIndexedSidePoints) {
      alignedSidePoints.add(data.$2);
      alignedSidePointsData.add(data);
    }

    _alignedSidePoints = alignedSidePoints;
    return alignedSidePointsData;
  }

  /// Returns a skew production between a vector AB and point C. If skew production (sk):
  /// - sk > 0, C is on the left relative to the vector.
  /// - sk == 0, C is on the vector/directly along the vector/behind the vector.
  /// - sk < 0, C is on the right relative to the vector.
  /// ``````
  /// https://acmp.ru/article.asp?id_text=172
  static double skewProduction(LatLng A, LatLng B, LatLng C) {
    // Remember that Lat is y on OY and Lng is x on OX => LatLng is (y,x), not (x,y)
    return ((B.longitude - A.longitude) * (C.latitude - A.latitude)) -
        ((B.latitude - A.latitude) * (C.longitude - A.longitude));
  }

  void _checkingPosition(
    List<LatLng> route,
    List<(int, LatLng, double)> alignedSidePointsData,
    List<LatLng> alignedSidePoints,
  ) {
    // [(wayPointIndex; sidePoint; right or left; past, next or on way; distance from current location;)]
    final List<(int, LatLng, String, String, double)> listOfData = [];
    late LatLng nextPoint;
    late LatLng closestPoint;
    late LatLng sidePoint;

    for (int i = 0; i < alignedSidePointsData.length; i++) {
      if (alignedSidePointsData[i].$1 == route.length - 1) {
        nextPoint = route[alignedSidePointsData[i].$1];
        closestPoint = route[alignedSidePointsData[i].$1 - 1];
      } else {
        nextPoint = route[alignedSidePointsData[i].$1 + 1];
        closestPoint = route[alignedSidePointsData[i].$1];
      }
      sidePoint = alignedSidePointsData[i].$2;

      // Vector AB, A - closestPoint, B - nextPoint, C - sidePoint
      final double skewProduct =
          skewProduction(closestPoint, nextPoint, sidePoint);

      skewProduct <= 0.0
          ? listOfData.add((
              alignedSidePointsData[i].$1,
              alignedSidePointsData[i].$2,
              'right',
              '',
              0,
            ))
          : listOfData.add((
              alignedSidePointsData[i].$1,
              alignedSidePointsData[i].$2,
              'left',
              '',
              0,
            ));
    }

    // We are starting at the beginning of the route
    const int startIndex = 0;
    bool firstNextFlag = true;
    for (int i = 0; i < listOfData.length; i++) {
      final (int, LatLng, String, String, double) data = listOfData[i];
      final double distance = getDistanceFromAToB(
        _route[startIndex],
        data.$2,
        aSegmentIndex: startIndex,
        bSegmentIndex: data.$1,
      ).$1;
      if (data.$1 <= startIndex) {
        listOfData[i] = (data.$1, data.$2, data.$3, 'past', distance);
      } else if (firstNextFlag && (data.$1 > startIndex)) {
        listOfData[i] = (data.$1, data.$2, data.$3, 'next', distance);
        firstNextFlag = false;
      } else {
        listOfData[i] = (data.$1, data.$2, data.$3, 'onWay', distance);
      }
    }

    for (final (int, LatLng, String, String, double) data in listOfData) {
      _sidePointsData
          .add((alignedSidePoints.indexOf(data.$2), data.$3, data.$4, data.$5));
      _sidePointsStatesHashTable[alignedSidePoints.indexOf(data.$2)] =
          (data.$1, data.$3, data.$4, data.$5);
    }
  }

  void _generatePointsAndWeights() {
    for (int i = 0; i < _lengthOfLists; i++) {
      _listOfPreviousCurrentLocations.add(_route[0]);
      _listOfWeights.add(1 / math.pow(2, i + 1));
    }
    _listOfWeights[0] += 1 / math.pow(2, _lengthOfLists);
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

  void _updateListOfPreviousLocations(LatLng currentLocation) {
    for (int i = _listOfPreviousCurrentLocations.length - 1; i > 0; i--) {
      _listOfPreviousCurrentLocations[i] =
          _listOfPreviousCurrentLocations[i - 1];
    }
    _listOfPreviousCurrentLocations[0] = currentLocation;
  }

  static double getAngleBetweenVectors(
      (double, double) v1, (double, double) v2) {
    final double dotProduct = v1.$1 * v2.$1 + v1.$2 * v2.$2;
    final double v1Length = math.sqrt(v1.$1 * v1.$1 + v1.$2 * v1.$2);
    final double v2Length = math.sqrt(v2.$1 * v2.$1 + v2.$2 * v2.$2);
    final double angle =
        toDegrees(math.acos((dotProduct / (v1Length * v2Length)).clamp(-1, 1)));
    return angle;
  }

  bool _isPointInLane(LatLng point, List<LatLng> lane) {
    int intersections = 0;
    for (int i = 0; i < lane.length; i++) {
      final LatLng a = lane[i];
      final LatLng b = lane[(i + 1) % lane.length];
      if ((a.longitude > point.longitude) != (b.longitude > point.longitude)) {
        final double intersect = (b.latitude - a.latitude) *
                (point.longitude - a.longitude) /
                (b.longitude - a.longitude) +
            a.latitude;
        if (point.latitude > intersect) {
          intersections++;
        }
      }
    }
    return intersections.isOdd;
  }

  bool isPointOnRouteByLanes({required LatLng point}) {
    late bool isInLane;
    for (int i = 0; i < _mapOfLanesData.length; i++) {
      final List<LatLng> lane = _mapOfLanesData[i]!.$1;
      isInLane = _isPointInLane(point, lane);
      if (isInLane) {
        break;
      }
    }
    return isInLane;
  }

  @Deprecated('Use [isPointOnRouteByLanes]')
  bool isPointOnRouteByRadius({required LatLng point, required double radius}) {
    if (radius.isNaN || radius.isNegative) {
      throw ArgumentError("Variable radius can't be NaN or negative");
    }

    double minDistance = double.infinity;
    for (final LatLng routePoint in _route) {
      final double distance = getDistance(point, routePoint);
      if (distance < minDistance) {
        minDistance = distance;
        if (minDistance < radius) {
          return true;
        }
      }
    }
    return false;
  }

  /// Searches for the most farthest from the beginning of the path segment and
  /// returns its index, which coincides with the index of the starting point of
  /// the segment in the path.
  int _findClosestSegmentIndex(LatLng currentLocation) {
    int closestSegmentIndex = -1;
    final Iterable<int> segmentIndexesInRoute = _mapOfLanesData.keys;
    final (double, double) motionVector = _calcWeightedVector(currentLocation);

    bool isCurrentLocationFound = false;
    for (int i = _previousSegmentIndex; i < segmentIndexesInRoute.length; i++) {
      final (List<LatLng>, (double, double)) laneData = _mapOfLanesData[i]!;
      final List<LatLng> lane = laneData.$1;
      final (double, double) routeVector = laneData.$2;

      final double angle = getAngleBetweenVectors(motionVector, routeVector);
      if (angle <= 46) {
        final bool isInLane = _isPointInLane(currentLocation, lane);
        if (isInLane) {
          closestSegmentIndex = i;
          isCurrentLocationFound = true;
        } else if (isCurrentLocationFound) {
          break;
        }
      } else if (isCurrentLocationFound) {
        break;
      }
    }

    if (!isCurrentLocationFound) {
      for (int i = 0; i < _previousSegmentIndex; i++) {
        final (List<LatLng>, (double, double)) laneData = _mapOfLanesData[i]!;
        final List<LatLng> lane = laneData.$1;
        final (double, double) routeVector = laneData.$2;

        final double angle = getAngleBetweenVectors(motionVector, routeVector);
        if (angle <= 46) {
          final bool isInLane = _isPointInLane(currentLocation, lane);
          if (isInLane) {
            closestSegmentIndex = i;
            isCurrentLocationFound = true;
          } else if (isCurrentLocationFound) {
            break;
          }
        } else if (isCurrentLocationFound) {
          break;
        }
      }
    }
    _isOnRoute = isCurrentLocationFound;
    return closestSegmentIndex;
  }

  void addListeners(void Function() listener) {
    _listeners.add(listener);
  }

  void updateListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// [(side point index in aligned side points; right or left; past, next or onWay)]
  /// ``````
  /// Updates side points' states by current location.
  List<(int, String, String, double)> updateStatesOfSidePoints(
      LatLng currentLocation) {
    updateListeners();
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int currentLocationIndex = _findClosestSegmentIndex(currentLocation);

    if (currentLocationIndex < 0 || currentLocationIndex >= _route.length) {
      print('[GeoUtils]: You are not on the route.');
      return [];
    } else {
      _coveredDistance +=
          getDistance(currentLocation, _listOfPreviousCurrentLocations[0]);
      _currentSegmentIndex = currentLocationIndex;

      _previousSegmentIndex = currentLocationIndex;
      _updateListOfPreviousLocations(currentLocation);
      _nextRoutePoint = (currentLocationIndex < (_route.length - 1))
          ? _route[currentLocationIndex + 1]
          : _route[currentLocationIndex];
      _nextRoutePointIndex = (currentLocationIndex < (_route.length - 1))
          ? currentLocationIndex + 1
          : currentLocationIndex;

      final List<(int, String, String, double)> newSidePointsData = [];
      final Iterable<int> sidePointIndexes = _sidePointsStatesHashTable.keys;
      bool firstNextFlag = true;

      for (final int i in sidePointIndexes) {
        final (int, String, String, double) data =
            _sidePointsStatesHashTable.update(i, (value) {
          if (value.$1 <= currentLocationIndex) {
            final double distance = getDistanceFromAToB(
                    currentLocation, _alignedSidePoints[i],
                    aSegmentIndex: currentLocationIndex,
                    bSegmentIndex: value.$1)
                .$1;
            return (value.$1, value.$2, 'past', distance);
          } else if (firstNextFlag && (value.$1 > currentLocationIndex)) {
            firstNextFlag = false;
            final double distance = getDistanceFromAToB(
                    currentLocation, _alignedSidePoints[i],
                    aSegmentIndex: currentLocationIndex,
                    bSegmentIndex: value.$1)
                .$1;
            return (value.$1, value.$2, 'next', distance);
          } else {
            final double distance = getDistanceFromAToB(
                    currentLocation, _alignedSidePoints[i],
                    aSegmentIndex: currentLocationIndex,
                    bSegmentIndex: value.$1)
                .$1;
            return (value.$1, value.$2, 'onWay', distance);
          }
        });

        newSidePointsData.add((i, data.$2, data.$3, data.$4));
      }

      _sidePointsData = newSidePointsData;
      return newSidePointsData;
    }
  }

  List<(int, String, String, double)> updateNStatesOfSidePoints(
      LatLng currentLocation,
      {int amountOfUpdatingSidePoints = 40}) {
    updateListeners();
    if (_amountOfUpdatingSidePoints < 0) {
      throw ArgumentError("amountOfUpdatingSidePoints can't be less then 0");
    }
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int currentLocationIndex = _findClosestSegmentIndex(currentLocation);

    if (currentLocationIndex < 0 || currentLocationIndex >= _route.length) {
      print('[GeoUtils]: You are not on the route.');
      return [];
    } else {
      _coveredDistance +=
          getDistance(currentLocation, _listOfPreviousCurrentLocations[0]);
      _currentSegmentIndex = currentLocationIndex;

      _previousSegmentIndex = currentLocationIndex;
      _updateListOfPreviousLocations(currentLocation);
      _nextRoutePoint = (currentLocationIndex < (_route.length - 1))
          ? _route[currentLocationIndex + 1]
          : _route[currentLocationIndex];
      _nextRoutePointIndex = (currentLocationIndex < (_route.length - 1))
          ? currentLocationIndex + 1
          : currentLocationIndex;

      final List<(int, String, String, double)> newSidePointsData = [];
      final Iterable<int> sidePointIndexes = _sidePointsStatesHashTable.keys;
      bool firstNextFlag = true;
      int sidePointsAmountCounter = 0;

      for (final int i in sidePointIndexes) {
        if (sidePointsAmountCounter >= _amountOfUpdatingSidePoints) {
          break;
        }

        final (int, String, String, double) data =
            _sidePointsStatesHashTable.update(i, (value) {
          if (value.$3 == 'past') {
            return value;
          }
          if (value.$1 <= currentLocationIndex) {
            final double distance = getDistanceFromAToB(
                    currentLocation, _alignedSidePoints[i],
                    aSegmentIndex: currentLocationIndex,
                    bSegmentIndex: value.$1)
                .$1;
            return (value.$1, value.$2, 'past', distance);
          } else if (firstNextFlag && (value.$1 > currentLocationIndex)) {
            firstNextFlag = false;
            final double distance = getDistanceFromAToB(
                    currentLocation, _alignedSidePoints[i],
                    aSegmentIndex: currentLocationIndex,
                    bSegmentIndex: value.$1)
                .$1;
            return (value.$1, value.$2, 'next', distance);
          } else {
            final double distance = getDistanceFromAToB(
                    currentLocation, _alignedSidePoints[i],
                    aSegmentIndex: currentLocationIndex,
                    bSegmentIndex: value.$1)
                .$1;
            return (value.$1, value.$2, 'onWay', distance);
          }
        });
        if (data.$3 != 'past') {
          newSidePointsData.add((i, data.$2, data.$3, data.$4));
          sidePointsAmountCounter++;
        }
      }

      _sidePointsData = newSidePointsData;
      return newSidePointsData;
    }
  }

  void updateCurrentLocation(LatLng currentLocation) {
    updateListeners();
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int currentLocationIndex = _findClosestSegmentIndex(currentLocation);

    if (currentLocationIndex < 0 || currentLocationIndex >= _route.length) {
      print('[GeoUtils]: You are not on the route.');
    } else {
      _coveredDistance +=
          getDistance(currentLocation, _listOfPreviousCurrentLocations[0]);
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
      final double newDistance = getDistance(point, _route[i]);

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
      print("[GeoUtils]: A, B or both doesn't lying on the route.");
      return (0, startSegmentIndex, endSegmentIndex);
    }

    (startSegmentIndex, endSegmentIndex, a, b) =
        (startSegmentIndex > endSegmentIndex)
            ? (endSegmentIndex, startSegmentIndex, b, a)
            : (startSegmentIndex, endSegmentIndex, a, b);

    final LatLng nearestToStartSegmentPoint = _route[startSegmentIndex + 1];
    // final LatLng nearestToEndSegmentPoint = _route[endSegmentIndex];
    double firstDistance = getDistance(a, nearestToStartSegmentPoint);
    // double secondDistance = getDistance(nearestToEndSegmentPoint, b);

    final (double, double) vector1 = (
      nearestToStartSegmentPoint.latitude - a.latitude,
      nearestToStartSegmentPoint.longitude - a.longitude
    );
    final (double, double) vector2 = _mapOfLanesData[startSegmentIndex]!.$2;
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

  List<LatLng> get alignedSidePoints => _alignedSidePoints;

  double get routeLength => _routeLength;

  LatLng get nextRoutePoint => _nextRoutePoint;

  int get nextRoutePointIndex => _nextRoutePointIndex;

  /// returns, are we still on route
  bool get isOnRoute => _isOnRoute;

  double get coveredDistance => _coveredDistance;

  bool get isFinished => _routeLength - _coveredDistance <= _finishLineDistance;

  int get currentSegmentIndex => _currentSegmentIndex;

  String get getVersion => routeManagerVersion;

  /// Returns a list [(side point index in aligned side points; right or left; past, next or onWay)].
  List<(int, String, String, double)> get sidePointsData => _sidePointsData;

  /// Returns a map {segment index in the route, (lane rectangular, (velocity vector: x, y))}.
  Map<int, (List<LatLng>, (double, double))> get mapOfLanesData =>
      _mapOfLanesData;

  Map<int, (int, String, String, double)> get sidePointsStatesHashTable => _sidePointsStatesHashTable;
}
