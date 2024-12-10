import 'dart:math' as math;

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
//TODO: найти причины сообщения о сходе с пути в приложении

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
class RouteManagerCore {
  RouteManagerCore({
    required List<LatLng> route,
    double laneWidth = 10,
    double laneExtension = 5,
    int lengthOfLists = 2,
  }) {
    _route = checkRouteForDuplications(route);
    _laneExtension = laneExtension;
    _laneWidth = laneWidth;
    _lengthOfLists = lengthOfLists >= 1
        ? lengthOfLists
        : throw ArgumentError('Length of lists must be equal or more then 1');

    for (int i = 0; i < (_route.length - 1); i++) {
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
    _generatePointsAndWeights();
  }

  static const double earthRadiusInMeters = 6371009.0;
  static const double metersPerDegree = 111195.0797343687;
  static const double sameCordConst = 0.0000005;

  List<LatLng> _route = [];
  late LatLng _nextRoutePoint;
  late int _nextRoutePointIndex;
  bool _isOnRoute = true;
  int _currentSegmentIndex = 0;

  late double _laneWidth;
  late double _laneExtension;

  /// {segment index in the route, (lane rectangular, (velocity vector: x (lat), y (lng) ))}
  final Map<int, (List<LatLng>, (double, double))> _mapOfLanesData = {};

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
              '[GeoUtils] Your route has a duplication of ${route[i]} (№${++counter}).');
        }
      }
    }
    print('[GeoUtils] Total amount of duplication $counter duplication');
    print('[GeoUtils]');
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

  void _generatePointsAndWeights() {
    for (int i = 0; i < _lengthOfLists; i++) {
      _listOfPreviousCurrentLocations.add(_route.first);
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

  /// Searches for the most farthest from the beginning of the path segment and
  /// returns its index, which coincides with the index of the starting point of
  /// the segment in the path.
  int _findClosestSegmentIndex(LatLng currentLocation) {
    int closestSegmentIndex = -1;
    final Iterable<int> segmentIndexesInRoute = _mapOfLanesData.keys;
    final (double, double) motionVector = _blocker > 0
        ? _mapOfLanesData[_previousSegmentIndex]!.$2
        : _calcWeightedVector(currentLocation);

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
        }
      }
      if (isCurrentLocationFound) break;
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
          }
        }
        if (isCurrentLocationFound) break;
      }
    }
    _isOnRoute = isCurrentLocationFound;
    return closestSegmentIndex;
  }

  void updateCurrentLocation(LatLng currentLocation) {
    // Uses the index of the current segment as the index of the point on the
    // path closest to the current location.
    final int currentLocationIndex = _findClosestSegmentIndex(currentLocation);

    if (currentLocationIndex < 0 || currentLocationIndex >= _route.length) {
      print('[GeoUtils] You are not on the route');
    } else {
      _updateListOfPreviousLocations(currentLocation);
      _currentSegmentIndex = currentLocationIndex;
      _previousSegmentIndex = currentLocationIndex > 0
          ? currentLocationIndex - 1
          : currentLocationIndex;
      _nextRoutePoint = (currentLocationIndex < (_route.length - 1))
          ? _route[currentLocationIndex + 1]
          : _route[currentLocationIndex];
      _nextRoutePointIndex = (currentLocationIndex < (_route.length - 1))
          ? currentLocationIndex + 1
          : currentLocationIndex;
    }
  }

  LatLng get nextRoutePoint => _nextRoutePoint;

  int get nextRoutePointIndex => _nextRoutePointIndex;

  /// returns, are we still on route
  bool get isOnRoute => _isOnRoute;

  int get currentSegmentIndex => _currentSegmentIndex;

  int get previousSegmentIndex => _previousSegmentIndex;

  List<LatLng> get route => _route;
}
