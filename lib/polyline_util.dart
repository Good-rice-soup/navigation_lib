// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';

class PolylineUtil {
  /// A simplified Ramer-Douglas-Peucker implementation to reduce polyline points
  static List<LatLng> simplifyRoutePoints(
      {required List<LatLng> points, double? tolerance}) {
    //The tolerance parameter in simplifyRoutePoints controls the degree of simplification. A higher value reduces more points.
    //0.0005  for length of route 1k points
    //0.01 // for length of route 20k points and more

    if (points.length < 1000 || tolerance == 0) return points;
    // No simplification needed for small lists or tolerance == 0

    // Recursive function for RDP simplification
    List<LatLng> rdp(List<LatLng> points, double epsilon) {
      double dmax = 0.0;
      int index = 0;

      for (int i = 1; i < points.length - 1; i++) {
        final double d =
            _perpendicularDistance(points[i], points[0], points.last);
        if (d > dmax) {
          index = i;
          dmax = d;
        }
      }

      if (dmax > epsilon) {
        // Recursive simplification
        final List<LatLng> firstHalf =
            rdp(points.sublist(0, index + 1), epsilon);
        final List<LatLng> secondHalf = rdp(points.sublist(index), epsilon);

        return firstHalf + secondHalf.sublist(1); // Combine results
      } else {
        return [points.first, points.last]; // Simplified line
      }
    }

    return rdp(points, tolerance ?? 0.00005);
    // 0.00005 reduce amount of points about x10 times
  }

  /// Calculate the perpendicular distance of a point from a line
  static double _perpendicularDistance(LatLng point, LatLng start, LatLng end) {
    final double dx = end.longitude - start.longitude;
    final double dy = end.latitude - start.latitude;

    if (dx == 0 && dy == 0) {
      return getDistance(p1: point, p2: start); // Start and end are the same
    }

    final double num = ((point.longitude - start.longitude) * dy -
            (point.latitude - start.latitude) * dx)
        .abs();
    final double den = sqrt(dx * dx + dy * dy);

    return num / den;
  }
}
