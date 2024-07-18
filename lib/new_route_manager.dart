import 'dart:math' as math;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

class NewRouteManager {
  NewRouteManager({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
    double laneWidth = 10,
    double laneExtension = 5,
    double finishLineDistance = 5,
    int lengthOfLists = 2,
  }) {
    _route = checkRouteForDuplications(route);
    _laneExtension = laneExtension;
    _laneWidth = laneWidth;
    _finishLineDistance = finishLineDistance;
    _lengthOfLists = lengthOfLists;

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

        _mapOfLanesData[i] = (
        _createLane(_route[i], _route[i + 1]),
        (
        _route[i + 1].latitude - _route[i].latitude,
        _route[i + 1].longitude - _route[i].longitude
        ),
        );
      }

      _alignedSidePoints = sidePoints;
      // By default we think that we are starting at the beginning of the route
      _nextRoutePoint = _route[1];

      if (sidePoints.isNotEmpty) {
        _checkingPosition(
            _route, _alignedSidePoints, _aligning(_route, sidePoints));
      }
      _generatePointsAndWeights();
    }
  }

  static const double earthRadiusInMeters = 6371009.0;
  static const double metersPerDegree = 111195.0797343687;

  List<LatLng> _route = [];
  double _routeLength = 0;
  late LatLng _nextRoutePoint;
  List<LatLng> _alignedSidePoints = [];

  late double _laneWidth;
  late double _laneExtension;
  late double _finishLineDistance;

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
  final List<double> _listOfWeights = [];
  late int _lengthOfLists;

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
      newRoute.add(route[route.length - 2]);
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
      LatLng(extendedStart.latitude + latNormal,
          extendedStart.longitude + lngNormal),
      LatLng(
          extendedEnd.latitude + latNormal, extendedEnd.longitude + lngNormal),
      LatLng(
          extendedEnd.latitude - latNormal, extendedEnd.longitude - lngNormal),
      LatLng(extendedStart.latitude - latNormal,
          extendedStart.longitude - lngNormal),
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
    // (wayPointIndex, sidePoint, distanceBetween)
    final List<(int, LatLng, double)> indexedSidePoints = [];
    for (final LatLng sidePoint in sidePoints) {
      indexedSidePoints.add((0, sidePoint, double.infinity));
    }

    for (int wayPointIndex = 0; wayPointIndex < route.length; wayPointIndex++) {
      for (int i = 0; i < sidePoints.length; i++) {
        final (int, LatLng, double) data = indexedSidePoints[i];
        final double distance = getDistance(data.$2, route[wayPointIndex]);
        if (distance < data.$3) {
          indexedSidePoints[i] = (wayPointIndex, data.$2, distance);
        }
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

  void _checkingPosition(
    List<LatLng> route,
    List<LatLng> alignedSidePoints,
    List<(int, LatLng, double)> alignedSidePointsData,
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

      // https://acmp.ru/article.asp?id_text=172
      // Vector AB, A - closestPoint, B - nextPoint, C - sidePoint
      // Remember that Lat is y on OY and Lng is x on OX!!!!! => LatLng is (y,x), not (x,y)
      final double skewProduction =
          ((nextPoint.longitude - closestPoint.longitude) *
                  (sidePoint.latitude - closestPoint.latitude)) -
              ((nextPoint.latitude - closestPoint.latitude) *
                  (sidePoint.longitude - closestPoint.longitude));

      skewProduction <= 0.0
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

    const int indexOfCurrentLocation = 0;
    bool firstNextFlag = true;
    for (int i = 0; i < listOfData.length; i++) {
      final (int, LatLng, String, String, double) data = listOfData[i];
      if (data.$1 <= indexOfCurrentLocation) {
        listOfData[i] = (
          data.$1,
          data.$2,
          data.$3,
          'past',
          -getDistanceFromAToB(_route[0], _route[data.$1]).$1
        );
      } else if (firstNextFlag && (data.$1 > indexOfCurrentLocation)) {
        listOfData[i] = (
          data.$1,
          data.$2,
          data.$3,
          'next',
          getDistanceFromAToB(_route[0], _route[data.$1]).$1
        );
        firstNextFlag = false;
      } else {
        listOfData[i] = (
          data.$1,
          data.$2,
          data.$3,
          'onWay',
          getDistanceFromAToB(_route[0], _route[data.$1]).$1
        );
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
      if ((a.latitude > point.latitude) != (b.latitude > point.latitude)) {
        final double intersect = (b.longitude - a.longitude) *
                (point.latitude - a.latitude) /
                (b.latitude - a.latitude) +
            a.longitude;
        if (point.longitude < intersect) {
          intersections++;
        }
      }
    }
    return intersections.isOdd;
  }

  /// Searches for the most farthest from the beginning of the path segment and
  /// returns its index, which coincides with the index of the starting point of
  /// the segment in the path.
  int _findClosestSegmentIndex(LatLng currentLocation) {
    int closestSegmentIndex = -1;
    final Iterable<int> segmentIndexesInRoute = _mapOfLanesData.keys;
    final (double, double) motionVector = _calcWeightedVector(currentLocation);

    bool isCurrentLocationFound = false;
    for (final int index in segmentIndexesInRoute) {
      final (List<LatLng>, (double, double)) laneData = _mapOfLanesData[index]!;
      final List<LatLng> lane = laneData.$1;
      final (double, double) routeVector = laneData.$2;

      final double angle = getAngleBetweenVectors(motionVector, routeVector);
      if (angle <= 46) {
        final bool isInLane = _isPointInLane(currentLocation, lane);
        if (isInLane) {
          closestSegmentIndex = index;
          isCurrentLocationFound = true;
        } else if (isCurrentLocationFound) {
          break;
        }
      } else if (isCurrentLocationFound) {
        break;
      }
    }
    return closestSegmentIndex;
  }

  /// [(side point index in aligned side points; right or left; past, next or onWay)]
  /// ``````
  /// Updates side points' states by current location.
  List<(int, String, String, double)> updateStatesOfSidePoints(
      LatLng currentLocation) {
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int currentLocationIndex = _findClosestSegmentIndex(currentLocation);

    if (currentLocationIndex < 0 || currentLocationIndex >= _route.length) {
      print('[GeoUtils]: You are not on the route.');
      return [];
    } else {
      _updateListOfPreviousLocations(currentLocation);
      _nextRoutePoint = (currentLocationIndex < (_route.length - 1))
          ? _route[currentLocationIndex + 1]
          : _route[currentLocationIndex];

      final List<(int, String, String, double)> newSidePointsData = [];
      final Iterable<int> sidePointIndexes = _sidePointsStatesHashTable.keys;
      bool firstNextFlag = true;

      for (final int index in sidePointIndexes) {
        final (int, String, String, double) data =
            _sidePointsStatesHashTable.update(index, (value) {
          if (value.$1 <= currentLocationIndex) {
            final double distance =
                -getDistanceFromAToB(currentLocation, _route[value.$1]).$1;
            return (value.$1, value.$2, 'past', distance);
          } else if (firstNextFlag && (value.$1 > currentLocationIndex)) {
            firstNextFlag = false;
            final double distance =
                getDistanceFromAToB(currentLocation, _route[value.$1]).$1;
            return (value.$1, value.$2, 'next', distance);
          } else {
            final double distance =
                getDistanceFromAToB(currentLocation, _route[value.$1]).$1;
            return (value.$1, value.$2, 'onWay', distance);
          }
        });

        newSidePointsData.add((index, data.$2, data.$3, data.$4));
      }

      _sidePointsData = newSidePointsData;
      return newSidePointsData;
    }
  }

  /// Primitive search by distance.
  int _primitiveFindClosestSegmentIndex(LatLng point) {
    // Searching by segments first point.
    const double radius = 10;
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
  (double, int, int) getDistanceFromAToB(LatLng A, LatLng B) {
    int startSegmentIndex = _primitiveFindClosestSegmentIndex(A);
    int endSegmentIndex = _primitiveFindClosestSegmentIndex(B);

    if (startSegmentIndex == -1 || endSegmentIndex == -1) {
      print("[GeoUtils]: A, B or both doesn't lying on the route.");
      return (0, startSegmentIndex, endSegmentIndex);
    }

    (startSegmentIndex, endSegmentIndex) = (startSegmentIndex > endSegmentIndex)
        ? (endSegmentIndex, startSegmentIndex)
        : (startSegmentIndex, endSegmentIndex);

    if (startSegmentIndex == endSegmentIndex) {
      return (getDistance(A, B), startSegmentIndex, endSegmentIndex);
    } else if (startSegmentIndex == (endSegmentIndex + 1)) {
      final LatLng middlePoint = _route[endSegmentIndex];
      final double firstDistance = getDistance(A, middlePoint);
      final double secondDistance = getDistance(middlePoint, B);

      final (double, double) vector1 = (
        B.latitude - middlePoint.latitude,
        B.longitude - middlePoint.longitude
      );
      final (double, double) vector2 = _mapOfLanesData[endSegmentIndex]!.$2;
      final double angle = getAngleBetweenVectors(vector1, vector2);
      final double distance = angle < 90
          ? firstDistance + secondDistance
          : firstDistance - secondDistance;
      return (distance, startSegmentIndex, endSegmentIndex);
    } else {
      final LatLng nearestToStartSegmentPoint = _route[startSegmentIndex + 1];
      final LatLng nearestToEndSegmentPoint = _route[endSegmentIndex];
      final double firstDistance = getDistance(A, nearestToStartSegmentPoint);
      final double secondDistance = getDistance(nearestToEndSegmentPoint, B);

      final (double, double) vector1 = (
        B.latitude - nearestToEndSegmentPoint.latitude,
        B.longitude - nearestToEndSegmentPoint.longitude
      );
      final (double, double) vector2 = _mapOfLanesData[endSegmentIndex]!.$2;
      final double angle = getAngleBetweenVectors(vector1, vector2);
      final double additionalDistance = angle < 90
          ? firstDistance + secondDistance
          : firstDistance - secondDistance;

      double distance = 0;
      for (int i = startSegmentIndex + 1; i < endSegmentIndex; i++) {
        distance += _segmentLengths[i]!;
      }
      distance += additionalDistance;

      return (distance, startSegmentIndex, endSegmentIndex);
    }
  }

  /// (covered distance, are we at finish line, segment index where current point is located)
  (double, bool, int) coveredDistance(LatLng currentLocation) {
    final (coveredDistance, _, locationSegmentIndex) =
        getDistanceFromAToB(_route[0], currentLocation);

    final bool isFinished =
        (_routeLength - coveredDistance) < _finishLineDistance;

    return (coveredDistance, isFinished, locationSegmentIndex);
  }

  List<LatLng> get alignedSidePoints => _alignedSidePoints;

  double get routeLength => _routeLength;

  LatLng get nextRoutePoint => _nextRoutePoint;

  /// Returns a list [(side point index in aligned side points; right or left; past, next or onWay)].
  List<(int, String, String, double)> get sidePointsData => _sidePointsData;

  /// Returns a map {segment index in the route, (lane rectangular, (velocity vector: x, y))}.
  Map<int, (List<LatLng>, (double, double))> get mapOfLanesData =>
      _mapOfLanesData;
}
