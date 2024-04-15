import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_hash_utils.dart';
import 'geo_math.dart';

///Class aggregator.
///
///The main purpose of this class is to partially combine the functionality of
///the GeoMath and GeohashUtils classes. It allows for more optimized
///calculations of:
///* Route length
/// * Conversion of the route to a list of geo hashes with a specified precision
/// * Alignment of side points relative to the route
/// * List of tuples containing the index of the side point in their aligned
/// list, its position relative to the route (right or left), and its state
/// (past, next, or onWay)
/// * Updating the states of side points
class GeoCalculationAggregator {
  ///Class constructor.
  ///
  ///The main parameter is the route represented as a list of coordinates.
  ///The route can be an empty list or contain one or more points.
  ///``````
  ///An additional parameter is sidePoints, which is empty by default but can
  ///be replaced with any other list of coordinates.
  ///``````
  ///If the route contains two or more different coordinates, the sidePoints
  ///are automatically aligned relative to it. For each of the points, the
  ///class field _sidePointsPlaceOnWay defines the tuple the index in the
  ///sorted list of all points, the side relative to the route (right or left),
  ///and their position on the route relative to the current location
  ///(past, next, or onWay) are also determined.
  ///``````
  ///The current location parameter represents a coordinate on the route and
  ///defaults to null. If it remains unchanged or does not belong to the route,
  ///it is replaced with the first point of the route during processing.
  ///``````
  ///The last parameter is the accuracy of calculating the geohash, which
  ///defaults to 5 characters. Changing the accuracy affects the length of
  ///the geohash.
  GeoCalculationAggregator({
    required List<LatLng> route,
    List<LatLng> sidePoints = const [],
    int precision = 5,
    LatLng? currentLocation,
  }) {
    _initObject(
      route: route,
      precision: precision,
      sidePoints: sidePoints,
      currentLocation: currentLocation,
    );
  }

  List<LatLng> _route = [];
  double _routeLength = 0;
  List<String> _wayGeoHashes = [];
  List<LatLng> _sidePoints = [];

  //(side point index in aligned side points; right or left; past, next or onWay)
  List<(int, String, String)> _sidePointsPlaceOnWay = [];

  //(side point index in aligned side points; closest way point index; right or left; past, next or onWay)
  Map<int, (int, String, String)> _hashTable = {};

  void _initObject({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
    required int precision,
    LatLng? currentLocation,
  }) {
    if (route.isEmpty) {
      _route = route;
      _routeLength = 0;
      _wayGeoHashes = [];
      _sidePoints = sidePoints;
      _sidePointsPlaceOnWay = [];
      _hashTable = {};
    } else if (route.length == 1) {
      _route = route;
      _routeLength = 0;
      _wayGeoHashes = [
        GeohashUtils.getGeoHashFromLocation(
            location: route[0], precision: precision)
      ];
      _sidePoints = sidePoints;
      _sidePointsPlaceOnWay = [];
      _hashTable = {};
    } else {
      _route = route;

      final Set<String> setOfGeoHashes = {};
      int duplicationCounter = 0;

      for (int i = 0; i < route.length - 1; i++) {
        _routeLength +=
            GeoMath.getDistance(point1: route[i], point2: route[i + 1]);
        setOfGeoHashes.add(GeohashUtils.getGeoHashFromLocation(
            location: route[i + 1], precision: precision));

        if (route[i] == route[i + 1]) {
          duplicationCounter++;
        }
      }
      //In process of iterations, the loop does not use i=0 for the setOfGeoHashes.
      setOfGeoHashes.add(GeohashUtils.getGeoHashFromLocation(
          location: route[0], precision: precision));

      _wayGeoHashes = setOfGeoHashes.toList();

      //Modified version of the function GeohashUtils.alignSidePointsV2().
      //
      // Added some functionality from GeohashUtils.checkPointSideOnWay3(),
      // as well as creating a hash table as a dictionary for more simplified
      // and optimized updating of the points' states relative to the current
      // location.
      _sidePoints = sidePoints;

      //checking, that routes like [LatLng(0,0), LatLng(0,0)] doesn't exist
      if (sidePoints.isNotEmpty && (route.length - duplicationCounter >= 2)) {
        final (List<LatLng>, List<(int, LatLng, double)>) temporaryData =
            _aligning(
          route: route,
          sidePoints: sidePoints,
        );

        final List<LatLng> alignedSidePoints = temporaryData.$1;
        final List<(int, LatLng, double)> alignedSidePointsData =
            temporaryData.$2;

        _sidePoints = alignedSidePoints;

        _checkingPosition(
          route: route,
          alignedSidePoints: alignedSidePoints,
          alignedSidePointsData: alignedSidePointsData,
          currentLocation: currentLocation,
        );
      }
    }
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
        final double distance = GeoMath.getDistance(
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
    required LatLng? currentLocation,
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

      final double dotProduction = GeohashUtils.dotProductionByPoints(
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

    currentLocation ??= route[0];

    final int indexOfCurrentLocation =
        !route.contains(currentLocation) ? 0 : route.indexOf(currentLocation);
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

  List<LatLng> getRoute() {
    return _route;
  }

  ///Works the same way, as the class constructor.
  ///``````
  ///The main parameter is the route represented as a list of coordinates.
  ///The route can be an empty list or contain one or more points.
  ///``````
  ///An additional parameter is sidePoints, which is empty by default but can
  ///be replaced with any other list of coordinates.
  ///``````
  ///If the route contains two or more different coordinates, the sidePoints
  ///are automatically aligned relative to it. For each of the points, the
  ///class field _sidePointsPlaceOnWay defines the tuple the index in the
  ///sorted list of all points, the side relative to the route (right or left),
  ///and their position on the route relative to the current location
  ///(past, next, or onWay) are also determined.
  ///``````
  ///The current location parameter represents a coordinate on the route and
  ///defaults to null. If it remains unchanged or does not belong to the route,
  ///it is replaced with the first point of the route during processing.
  ///``````
  ///The last parameter is the accuracy of calculating the geohash, which
  ///defaults to 5 characters. Changing the accuracy affects the length of
  ///the geohash.
  void changeRoute({
    required List<LatLng> newRoute,
    List<LatLng> sidePoints = const [],
    int precision = 5,
    LatLng? currentLocation,
  }) {
    _initObject(
      route: newRoute,
      sidePoints: sidePoints,
      precision: precision,
      currentLocation: currentLocation,
    );
  }

  double getRouteLength() {
    return _routeLength;
  }

  List<String> getWayGeoHashes() {
    return _wayGeoHashes;
  }

  ///Allows recalculating geo hashes with a specified precision. It does not
  ///modify the route or other parameters.
  void recalculateWayGeoHashes({int precision = 5}) {
    _wayGeoHashes =
        GeohashUtils.getWayGeoHashes(points: _route, precision: precision);
  }

  List<LatLng> getSidePoints() {
    return _sidePoints;
  }

  List<(int, String, String)> getSidePointsPlaceOnWay() {
    return _sidePointsPlaceOnWay;
  }

  ///The function takes the index of the current location in the list of route
  ///coordinates and compares it with the indexes closest to the side points'
  ///coordinates on the route, thereby updating side points' state. If the
  ///accepted value is greater or less than the permissible index values for
  ///the route coordinates, the function does not change the state of the
  ///side points.
  void updateSidePointsPlaceOnWay({required int newCurrentLocationIndex}) {
    if (_hashTable.isEmpty ||
        newCurrentLocationIndex < 0 ||
        newCurrentLocationIndex >= _route.length) {
      return;
    } else {
      final Iterable<int> keys = _hashTable.keys;
      bool firstNextFlag = true;
      final List<(int, String, String)> newSidePointsPlaceOnWay = [];

      for (final int key in keys) {
        _hashTable.update(key, (value) {
          if (value.$1 <= newCurrentLocationIndex) {
            return (value.$1, value.$2, 'past');
          } else if (firstNextFlag && (value.$1 > newCurrentLocationIndex)) {
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
    }
  }
}
