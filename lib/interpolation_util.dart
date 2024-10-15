import 'dart:async';
import 'dart:math' as math;

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

class Interpolation {
  Interpolation({this.time = const Duration(milliseconds: 200)});

  static const double metersPerDegree = 111195.0797343687;
  static const double earthRadiusInMeters = 6371009.0;

  final Duration time;

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

  void getRoutePoints({
    required LatLng start,
    required LatLng end,
    required LatLng Function() updatePoints,
    double epsilon = 0.00002,
  }) {
    final List<LatLng> interpolatedPoints =
        _getInterpolatedPoints(start: start, end: end, epsilon: epsilon);
    int currentIndex = 0;

    Timer.periodic(time, (timer) {
      if (currentIndex < interpolatedPoints.length) {
        updatePoints();
        currentIndex++;
      } else {
        updatePoints();
        timer.cancel();
      }
    });
  }
}
