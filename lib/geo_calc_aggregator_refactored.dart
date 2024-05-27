import 'dart:math' as math;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

class GeoCalculationAggregatorRef {
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
  GeoCalculationAggregatorRef({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
  }) {
    if (route.isEmpty) {
      _route = route;
      _routeLength = 0;
      _sidePointsPlaceOnWay = [];
      _hashTable = {};
    } else if (route.length == 1) {
      _route = route;
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


        _checkingPosition(
          route: route,
          alignedSidePoints: alignedSidePoints,
          alignedSidePointsData: alignedSidePointsData,
        );
      }
    }
  }

  List<LatLng> _route = [];
  LatLng _nextRoutePoint = const LatLng(0, 0);
  double _routeLength = 0;

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

  ///The function takes vector AB in the format of LatLng coordinates A and B,
  ///along with an additional LatLng coordinate C, and calculates the dot
  ///product between vector AB and point C.
  double _dotProductionByPoints(
      {required LatLng A, required LatLng B, required LatLng C}) {
    final List<double> vectorAB = [
      B.latitude - A.latitude,
      B.longitude - A.longitude
    ];
    final List<double> vectorAC = [
      C.latitude - A.latitude,
      C.longitude - A.longitude
    ];

    final double dotProduction =
        vectorAC[0] * vectorAB[0] + vectorAC[1] * vectorAB[1];
    return dotProduction;
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

      // Creates a vector in the direction of motion, constructs its right
      // perpendicular, and returns the point forming the right perpendicular.
      final LatLng rightPerpendicularPoint = LatLng(
        (nextPoint.longitude - closestPoint.longitude) + closestPoint.latitude,
        -(nextPoint.latitude - closestPoint.latitude) + closestPoint.longitude,
      );

      final double dotProduction = _dotProductionByPoints(
        A: closestPoint,
        B: rightPerpendicularPoint,
        C: sidePoint,
      );

      dotProduction >= 0
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

    _nextRoutePoint = route[1];

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

  int _findClosestWayPoint({required LatLng currentLocation}) {
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

  double get routeLength => _routeLength;

  LatLng get nextRoutePoint => _nextRoutePoint;

  List<(int, String, String)> get sidePointsPlaceOnWay => _sidePointsPlaceOnWay;

  ///The function takes the coordinates of the current location and updates the
  ///position of the coordinates on the route relative to the new position. If
  ///the new position is not on the route and is more than 500 meters away from
  ///any point on the route, the function throws an argument error.
  List<(int, String, String)> updateCurrentLocation(
      {required LatLng newCurrentLocation}) {
    final int index = _route.indexOf(newCurrentLocation);
    final int currentLocationIndex = index == -1
        ? _findClosestWayPoint(currentLocation: newCurrentLocation)
        : index;

    if (_hashTable.isEmpty ||
        currentLocationIndex < 0 ||
        currentLocationIndex >= _route.length) {
      throw ArgumentError('Smt is wrong with hashtable or current location');
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
}
