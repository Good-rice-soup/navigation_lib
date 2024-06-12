import 'dart:math' as math;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

/// Constructor arguments:
///
/// This class takes a list of route coordinates and a list of side point coordinates.
/// Either of the lists (or both simultaneously) can be empty without causing an error.
///``````
/// Main tasks of the class:
/// - Automatically align side points along the route.
/// - Efficiently update the state of side points via the updateCurrentLocation method.
/// - Automatically calculate the length of the route and the next point.
///``````
/// Method updateCurrentLocation:
///
/// This method takes a new currentLocation and updates the states of the side points.
/// Side points are attached to the nearest route points. When we are at the route point to which
/// a side point is attached, it (and all side points up to it) changes its state to 'past'. The next
/// side point in the aligned side point's list changes its state from 'onWay' to 'next'.
///``````
/// If the new currentLocation is not on the route but is within 5 meters of one of the route
/// points, the nearest route point will be used to update the states. Otherwise, the first route
/// point will be used, and the method will throw an argument error.
///
/// Ways to break the class:
/// - Allowing duplicate coordinates in side points. Before the first update of currentLocation,
///   the states will contain all duplicates, and after the update, all unique points will remain
///   in the list. The class will continue to work, but it will require extra attention to the
///   first value of (int, String, String) in alignedSidePoints.
/// - Allowing duplicate coordinates in the route. The class will continue to work, but there is a
///   risk of incorrect calculation of the side points' states (left or right of the route).
/// - When attaching multiple side points to one route point, upon reaching this route point, all
///   attached side points will simultaneously acquire the status 'past'.
class RouteManager {
  ///Class constructor.
  ///
  ///The route represented as a list of coordinates. The route can be an empty
  ///list or contain one or more points.
  ///``````
  ///Side points have the same properties as the route.
  ///``````
  ///If the route contains two or more different coordinates, the sidePoints
  ///are automatically aligned relative to it. For each of the points, the
  ///class field _sidePointsPlaceOnWay defines the tuple the index in the
  ///sorted list of all points, the side relative to the route (right or left),
  ///and their position on the route relative to the beginning of the road
  ///(past, next, or onWay) are also determined.
  RouteManager({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
  }) {
    if (route.isEmpty) {
      _route = route;
      _alignedSidePoints = sidePoints;
      _routeLength = 0;
      _sidePointsPlaceOnWay = [];
      _hashTable = {};
    } else if (route.length == 1) {
      _route = route;
      _alignedSidePoints = sidePoints;
      _routeLength = 0;
      _sidePointsPlaceOnWay = [];
      _hashTable = {};
    } else {
      _route = route;
      int duplicationCounter = 0;

      for (int i = 0; i < route.length - 1; i++) {
        _routeLength += _getDistance(point1: route[i], point2: route[i + 1]);
        if (route[i] == route[i + 1]) {
          duplicationCounter++;
        }
      }

      //It will return us an ordinary side points if route =
      // [LatLng(0,0), LatLng(0,0)]
      _alignedSidePoints = sidePoints;
      //By default we think that we are starting at the beginning of the route
      _nextRoutePoint = route[1];

      //Modified version of the function GeohashUtils.alignSidePointsV2().
      //
      // Added some functionality from GeohashUtils.checkPointSideOnWay3(),
      // as well as creating a hash table as a dictionary for more simplified
      // and optimized updating of the points' states relative to the current
      // location.

      //checking, that routes like [LatLng(0,0), LatLng(0,0)] doesn't exist
      if (sidePoints.isNotEmpty && (route.length - duplicationCounter >= 2)) {
        final (List<LatLng>, List<(int, LatLng, double)>) buffer = _aligning(
          route: route,
          sidePoints: sidePoints,
        );

        final List<LatLng> alignedSidePoints = buffer.$1;
        final List<(int, LatLng, double)> alignedSidePointsData = buffer.$2;
        _alignedSidePoints = alignedSidePoints;

        _checkingPosition(
          route: route,
          alignedSidePoints: alignedSidePoints,
          alignedSidePointsData: alignedSidePointsData,
        );
      }
    }
  }

  List<LatLng> _route = [];
  List<LatLng> _alignedSidePoints = [];
  LatLng _nextRoutePoint = const LatLng(0, 0);
  double _routeLength = 0;
  double _researchRadius = 5;

  //(side point index in aligned side points; right or left; past, next or onWay)
  List<(int, String, String)> _sidePointsPlaceOnWay = [];

  //(side point index in aligned side points; closest way point index; right or left; past, next or onWay)
  Map<int, (int, String, String)> _hashTable = {};

  static double _getDistance({required LatLng point1, required LatLng point2}) {
    const double earthRadius = 6371009.0; //in meters

    final double lat1 = point1.latitude;
    final double lon1 = point1.longitude;

    final double lat2 = point2.latitude;
    final double lon2 = point2.longitude;

    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double haversinLat = math.pow(math.sin(dLat / 2), 2).toDouble();
    final double haversinLon = math.pow(math.sin(dLon / 2), 2).toDouble();

    final double a = haversinLat +
        haversinLon * math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2));
    final double c = 2 * math.asin(math.sqrt(a));

    return earthRadius * c;
  }

  static double _toRadians(double deg) {
    return deg * (math.pi / 180);
  }

  (List<LatLng>, List<(int, LatLng, double)>) _aligning({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
  }) {
    //GeohashUtils.alignSidePointsV2() part
    List<(int, LatLng, double)> indexedSidePoints = [];

    for (final LatLng sidePoint in sidePoints) {
      //(wayPointIndex, sidePoint, distanceBetween)
      indexedSidePoints.add((0, sidePoint, double.infinity));
    }

    for (int wayPointIndex = 0; wayPointIndex < route.length; wayPointIndex++) {
      for (int i = 0; i < indexedSidePoints.length; i++) {
        final (int, LatLng, double) list = indexedSidePoints[i];
        final double distance = _getDistance(
          point1: list.$2,
          point2: route[wayPointIndex],
        );
        if (distance < list.$3) {
          indexedSidePoints[i] = (wayPointIndex, list.$2, distance);
        }
      }
    }

    //special conditions for zero indexed side points
    final List<(int, LatLng, double)> zeroIndexedSidePoints = [];
    if (indexedSidePoints.any((element) => element.$1 == 0)) {
      final List<(int, LatLng, double)> newIndexedSidePoints = [];
      for (final (int, LatLng, double) list in indexedSidePoints) {
        list.$1 == 0
            ? zeroIndexedSidePoints.add(list)
            : newIndexedSidePoints.add(list);
      }
      indexedSidePoints = newIndexedSidePoints;
    }

    indexedSidePoints.sort((a, b) => a.$1.compareTo(b.$1) != 0
        ? a.$1.compareTo(b.$1)
        : a.$3.compareTo(b.$3));

    final List<LatLng> alignedSidePoints = [];
    final List<(int, LatLng, double)> alignedSidePointsData = [];

    if (zeroIndexedSidePoints.isNotEmpty) {
      zeroIndexedSidePoints.sort((a, b) => a.$1.compareTo(b.$1) != 0
          ? a.$1.compareTo(b.$1)
          : -1 * a.$3.compareTo(b.$3));

      for (final (int, LatLng, double) list in zeroIndexedSidePoints) {
        alignedSidePoints.add(list.$2);
        alignedSidePointsData.add(list);
      }
    }

    for (final (int, LatLng, double) list in indexedSidePoints) {
      alignedSidePoints.add(list.$2);
      alignedSidePointsData.add(list);
    }

    return (alignedSidePoints, alignedSidePointsData);
  }

  void _checkingPosition({
    required List<LatLng> route,
    required List<LatLng> alignedSidePoints,
    required List<(int, LatLng, double)> alignedSidePointsData,
  }) {
    //GeohashUtils.checkPointSideOnWay3() part
    //
    //(wayPointIndex; sidePoint; distanceBetween; right or left; past, next or on way;)
    final List<(int, LatLng, double, String, String)> data = [];
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

      //https://acmp.ru/article.asp?id_text=172
      //https://ru.wikipedia.org/wiki/%D0%9F%D1%81%D0%B5%D0%B2%D0%B4%D0%BE%D1%81%D0%BA%D0%B0%D0%BB%D1%8F%D1%80%D0%BD%D0%BE%D0%B5_%D0%BF%D1%80%D0%BE%D0%B8%D0%B7%D0%B2%D0%B5%D0%B4%D0%B5%D0%BD%D0%B8%D0%B5
      //vector AB, A - closestPoint, B - nextPoint, C - sidePoint
      //remember that Lat is y on OY and Lng is x on OX!!!!! => LatLng is (y,x), not (x,y)
      final double skewProduction =
          ((nextPoint.longitude - closestPoint.longitude) *
                  (sidePoint.latitude - closestPoint.latitude)) -
              ((nextPoint.latitude - closestPoint.latitude) *
                  (sidePoint.longitude - closestPoint.longitude));

      skewProduction <= 0.0
          ? data.add((
              alignedSidePointsData[i].$1,
              alignedSidePointsData[i].$2,
              alignedSidePointsData[i].$3,
              'right',
              '',
            ))
          : data.add((
              alignedSidePointsData[i].$1,
              alignedSidePointsData[i].$2,
              alignedSidePointsData[i].$3,
              'left',
              '',
            ));
    }

    const int indexOfCurrentLocation = 0;
    bool firstNextFlag = true;

    for (int i = 0; i < data.length; i++) {
      if (data[i].$1 <= indexOfCurrentLocation) {
        data[i] = (data[i].$1, data[i].$2, data[i].$3, data[i].$4, 'past');
      } else if (firstNextFlag && (data[i].$1 > indexOfCurrentLocation)) {
        data[i] = (data[i].$1, data[i].$2, data[i].$3, data[i].$4, 'next');
        firstNextFlag = false;
      } else {
        data[i] = (data[i].$1, data[i].$2, data[i].$3, data[i].$4, 'onWay');
      }
    }

    for (final (int, LatLng, double, String, String) list in data) {
      _sidePointsPlaceOnWay
          .add((alignedSidePoints.indexOf(list.$2), list.$4, list.$5));
      _hashTable[alignedSidePoints.indexOf(list.$2)] =
          (list.$1, list.$4, list.$5);
    }
  }

  ///modified
  int _findClosestWayPointV2({required LatLng currentLocation}) {
    final double radius = _researchRadius;
    double distance = double.infinity;
    int closestRouteIndex = -1;

    //takes pairs of route points to guarantee the order
    for (int i = 1; i < _route.length; i++) {
      final double fistPointDistance =
          _getDistance(point1: currentLocation, point2: _route[i - 1]);
      final double secondPointDistance =
          _getDistance(point1: currentLocation, point2: _route[i]);

      final bool distanceCondition = (fistPointDistance < distance) &&
          (fistPointDistance < secondPointDistance);
      final bool radiusCondition = fistPointDistance < radius;

      if (distanceCondition && radiusCondition) {
        closestRouteIndex = i - 1;
        distance = fistPointDistance;
      }
    }

    final double lastPointDistance = _getDistance(
      point1: currentLocation,
      point2: _route[_route.length - 1],
    );
    if ((lastPointDistance < distance) && (lastPointDistance < radius)) {
      closestRouteIndex = _route.length - 1;
    }

    return closestRouteIndex;
  }

  ///original
  int _findClosestWayPointV1({required LatLng currentLocation}) {
    const double radius = 500;
    double distance = double.infinity;
    int closestRouteIndex = -1;

    for (int i = 0; i < _route.length; i++) {
      final double newDistance =
          _getDistance(point1: currentLocation, point2: _route[i]);

      if ((newDistance < distance) && (newDistance < radius)) {
        closestRouteIndex = i;
        distance = newDistance;
      }
    }
    return closestRouteIndex;
  }

  int _findClosestWayPoint({
    required LatLng currentLocation,
    required String researchFuncVersion,
  }) {
    return researchFuncVersion == 'v1'
        ? _findClosestWayPointV1(currentLocation: currentLocation)
        : _findClosestWayPointV2(currentLocation: currentLocation);
  }

  List<LatLng> get alignedSidePoints => _alignedSidePoints;

  double get routeLength => _routeLength;

  LatLng get nextRoutePoint => _nextRoutePoint;

  List<(int, String, String)> get sidePointsPlaceOnWay => _sidePointsPlaceOnWay;

  ///The function takes the coordinates of the current location and updates the
  ///position of the coordinates on the route relative to the new position. If
  ///the new position is not on the route and is more than 500 meters away from
  ///any point on the route, the function throws an argument error and use first
  ///route coordinate for calculations.
  List<(int, String, String)> updateCurrentLocation(
      {required LatLng newCurrentLocation, String researchFuncVersion = 'v1'}) {
    final int index = _route.indexOf(newCurrentLocation);
    final int currentLocationIndex = (index == -1)
        ? _findClosestWayPoint(
            currentLocation: newCurrentLocation,
            researchFuncVersion: researchFuncVersion,
          )
        : index;

    _nextRoutePoint = (currentLocationIndex < (_route.length - 1))
        ? _route[currentLocationIndex + 1]
        : _route[currentLocationIndex];

    if (currentLocationIndex < 0 || currentLocationIndex >= _route.length) {
      throw ArgumentError('Smt is wrong with current location');
    } else {
      final Iterable<int> keys = _hashTable.keys;
      bool firstNextFlag = true;
      final List<(int, String, String)> newSidePointsPlaceOnWay = [];

      for (final int key in keys) {
        _hashTable.update(key, (value) {
          if (value.$1 <= currentLocationIndex) {
            return (value.$1, value.$2, 'past');
          } else if (firstNextFlag && (value.$1 > currentLocationIndex)) {
            firstNextFlag = false;
            return (value.$1, value.$2, 'next');
          } else {
            return (value.$1, value.$2, 'onWay');
          }
        });

        newSidePointsPlaceOnWay.add((
          key,
          _hashTable[key]!.$2,
          _hashTable[key]!.$3,
        ));
      }

      _sidePointsPlaceOnWay = newSidePointsPlaceOnWay;
      return newSidePointsPlaceOnWay;
    }
  }

  ///Takes new research radius for _findClosestWayPoint.
  set newResearchRadius(double researchRadius) {
    if (researchRadius > 0) {
      _researchRadius = researchRadius;
    }
  }
}
