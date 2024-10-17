import 'dart:async';
//import 'dart:math' as math;

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'geo_hash_utils.dart';

class Interpolation {
  Interpolation({
    this.interpolationTime = const Duration(milliseconds: 200),
    this.ttl = const Duration(seconds: 5),
  });

  static const double metersPerDegree = 111195.0797343687;
  static const double earthRadiusInMeters = 6371009.0;

  final Duration interpolationTime;
  final Duration ttl; // time to live

  /*
  it works
  /// Degrees to radians.
  double _toRadians(double deg) {
    return deg * (math.pi / 180);
  }

  /// Get distance between two points.
  double _getDistance(LatLng point1, LatLng point2) {
    final double deltaLat = _toRadians(point2.latitude - point1.latitude);
    final double deltaLon = _toRadians(point2.longitude - point1.longitude);

    final double haversinLat = math.pow(math.sin(deltaLat / 2), 2).toDouble();
    final double haversinLon = math.pow(math.sin(deltaLon / 2), 2).toDouble();
    final double parameter = math.cos(_toRadians(point1.latitude)) *
        math.cos(_toRadians(point2.latitude));
    final double asinArgument =
        math.sqrt(haversinLat + haversinLon * parameter).clamp(-1, 1);

    return earthRadiusInMeters * 2 * math.asin(asinArgument);
  }
   */

  /*
  it works

  //epsilon is how smooth it should in LatLng degrees
  List<LatLng> _getInterpolatedPoints({
    required LatLng start,
    required LatLng end,
    required double epsilon,
  }) {
    final double distance = _getDistance(start, end);
    final double degrees = distance / metersPerDegree;
    int numPoints = (degrees / epsilon).ceil();
    if (numPoints < 1) numPoints = 1;

    return _interpolatePoints(start, end, numPoints);
  }
   */

  static List<LatLng> _interpolatePoints(LatLng p1, LatLng p2, int numPoints) {
    final List<LatLng> interpolatedPoints = [];
    for (int i = 1; i <= numPoints; i++) {
      final double fraction = i / (numPoints + 1);
      final double lat = p1.latitude + (p2.latitude - p1.latitude) * fraction;
      final double lng =
          p1.longitude + (p2.longitude - p1.longitude) * fraction;
      interpolatedPoints.add(LatLng(lat, lng));
    }
    return interpolatedPoints;
  }

  /*
  it is working
  List<LatLng> _getInterpolatedRoute({
    required List<LatLng> route,
    required double epsilon,
  }) {
    if (route.length < 2) {
      return route;
    }
    final List<LatLng> interpolatedPoints = _getInterpolatedPoints(
      start: route[0],
      end: route[1],
      epsilon: epsilon,
    );
    final List<LatLng> updatedRoute = [
      ...interpolatedPoints,
      ...route.sublist(2),
    ];
    return updatedRoute;
  }
   */

  /// start and end time in milliseconds
  void getRoutePoints({
    required LatLng start,
    required int startTime,
    required LatLng end,
    required int endTime,
    required LatLng Function() updatePoints,
    double epsilon = 0.00002,
  }) {
    final int time = endTime - startTime;
    if (time > ttl.inMilliseconds) {
      updatePoints();
      return;
    }
    final int amountOfPoints = (time / interpolationTime.inMilliseconds).ceil();
    final List<LatLng> interpolatedPoints =
        _interpolatePoints(start, end, amountOfPoints);
    int currentIndex = 0;

    Timer.periodic(interpolationTime, (timer) {
      if (currentIndex < interpolatedPoints.length) {
        updatePoints();
        currentIndex++;
      } else {
        updatePoints();
        timer.cancel();
      }
    });
  }

  bool _isPointInBounds(LatLng point, LatLngBounds bounds) {
    return point.latitude >= bounds.southwest.latitude &&
        point.latitude <= bounds.northeast.latitude &&
        point.longitude >= bounds.southwest.longitude &&
        point.longitude <= bounds.northeast.longitude;
  }

  List<String> getVisiblePartGeoHashesByRoute({
    required List<LatLng> route,
    required LatLngBounds bounds,
    required int precision,
  }) {
    final List<String> result = [];
    for (final LatLng point in route) {
      if (_isPointInBounds(point, bounds)) {
        result.add(GeohashUtils.getGeoHashFromLocation(
            location: point, precision: precision));
      }
    }
    return result;
  }

  List<String> getVisiblePartGeoHashes({
    required List<LatLng> visiblePart,
    required LatLngBounds bounds,
    required int precision,
  }) {
    final List<String> result = [];
    for (final LatLng point in visiblePart) {
      result.add(GeohashUtils.getGeoHashFromLocation(
          location: point, precision: precision));
    }
    return result;
  }
}
