import 'dart:math' as math;

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'config_classes.dart';

class Interpolation {
  Interpolation({required this.zoomConfigSet});

  static const double metersPerDegree = 111195.0797343687;
  static const double earthRadiusInMeters = 6371009.0;

  final Set<ZoomToFactor> zoomConfigSet;

  ZoomToFactor _getZoomConfig(int zoom) {
    return zoomConfigSet.firstWhere(
      (config) => config.zoom == zoom,
    );
  }

  /// Degrees to radians.
  static double toRadians(double deg) {
    return deg * (math.pi / 180);
  }

  /// Radians to degrees.
  static double toDegrees(double rad) {
    return rad * (180 / math.pi);
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

  List<LatLng> getInterpolatedPoints({
    required LatLng start,
    required LatLng end,
    required int currentZoomLevel,
  }) {
    final ZoomToFactor zoomConfig = _getZoomConfig(currentZoomLevel);
    final double distance = getDistance(start, end);
    final double degrees = distance / metersPerDegree;
    int numPoints = (degrees / zoomConfig.routeSimplificationFactor).ceil();
    if (numPoints < 1) numPoints = 1;

    return interpolatePoints(start, end, numPoints);
  }

  static List<LatLng> interpolatePoints(LatLng p1, LatLng p2, int numPoints) {
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

  List<LatLng> getInterpolatedRoute({
    required List<LatLng> route,
    required int currentZoomLevel,
  }) {
    if (route.length < 2) {
      return route;
    }
    final List<LatLng> interpolatedPoints = getInterpolatedPoints(
      start: route[0],
      end: route[1],
      currentZoomLevel: currentZoomLevel,
    );
    final List<LatLng> updatedRoute = [
      ...interpolatedPoints,
      ...route.sublist(2),
    ];
    return updatedRoute;
  }
}
