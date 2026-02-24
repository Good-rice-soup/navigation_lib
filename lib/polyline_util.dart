import 'dart:math';
import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';

/// Simplifies a given polyline using the Ramer-Douglas-Peucker (RDP) algorithm.
///
/// [mapping] - an optional map to store the relationship between the indices
/// of the new simplified route and the original route (simplified_index : original_index).
/// Returns a new List<LatLng> representing the simplified route.
List<LatLng> rdpRouteSimplifier(
    List<LatLng> route,
    double toleranceInM, {
      int ignoreIfLess = 300,
      Map<int, int>? mapping,
    }) {
  // 1. Edge cases: If the route is too short, or tolerance is 0, return a copy.
  if (route.length < 2 || toleranceInM <= 0 || route.length <= ignoreIfLess) {
    if (mapping != null) {
      for (int i = 0; i < route.length; i++) {
        mapping[i] = i;
      }
    }
    return List<LatLng>.from(route);
  }

  // Use squared tolerance to avoid expensive sqrt() calculations later.
  final double epsilonSq = toleranceInM * toleranceInM;

  // A flat bitmask array to keep track of which points to keep (1 = keep, 0 = drop).
  final Uint8List preserved = Uint8List(route.length);

  // Custom stack to avoid deep recursion and prevent stack overflow on huge routes.
  // Stores the start and end indices of the segments to process.
  final List<({int s, int e})> stack =
  List<({int s, int e})>.filled(128, (s: 0, e: 0), growable: true);
  int stackSize = 1;

  // Initially, push the entire route onto the stack.
  stack[0] = (s: 0, e: route.length - 1);

  // The very first and very last points of the original route must always be preserved.
  preserved[0] = 1;
  preserved[route.length - 1] = 1;

  // Track exactly how many points we are preserving to allocate the final list efficiently.
  int preservedCount = 2; // Starts at 2 for the first and last points.

  while (stackSize > 0) {
    // Pop the current segment from the stack.
    final (:s, :e) = stack[--stackSize];
    final int start = s;
    final int end = e;
    final LatLng startPoint = route[start];
    final LatLng endPoint = route[end];

    // 2. Equirectangular projection (Flat-Earth approximation).
    // To avoid heavy spherical geometry (Haversine) in the inner loop, we project
    // Lat/Lng degrees into local meters based on the segment's average latitude.
    final double avgLat = (startPoint.latitude + endPoint.latitude) / 2;

    // The length of a longitude degree shrinks as we move towards the poles (proportional to cos(latitude)).
    final double lonToMeters = cos(toRadians(avgLat)) * metersPerDegree;
    const double latToMeters = metersPerDegree;

    // Convert degrees to approximate local meters.
    final double startX = startPoint.longitude * lonToMeters;
    final double startY = startPoint.latitude * latToMeters;
    final double endX = endPoint.longitude * lonToMeters;
    final double endY = endPoint.latitude * latToMeters;

    // Vector representing the current line segment.
    final double dx = endX - startX;
    final double dy = endY - startY;

    double maxDistSq = 0.0;
    int maxIndex = start;

    // 3. Finding the furthest point from the line segment.
    if (dx != 0.0 || dy != 0.0) {
      // NORMAL CASE: The segment has length.
      // We use the 2D cross product (pseudo-scalar product) to find the perpendicular distance.
      // The cross product gives the area of a parallelogram. Area / base length = height (distance).
      final double invDenominator = 1.0 / (dx * dx + dy * dy);

      for (int i = start + 1; i < end; i++) {
        final LatLng point = route[i];
        final double px = point.longitude * lonToMeters;
        final double py = point.latitude * latToMeters;

        // Numerator represents the squared area of the parallelogram.
        final double numerator = (px - startX) * dy - (py - startY) * dx;

        // Squared perpendicular distance from the point to the line.
        final double distSq = numerator * numerator * invDenominator;

        if (distSq > maxDistSq) {
          maxDistSq = distSq;
          maxIndex = i;
        }
      }
    } else {
      // EDGE CASE: Start and end points are exactly the same (e.g., a closed polygon loop).
      // The segment collapses into a single point.
      // We simply calculate the standard squared Euclidean distance from intermediate points to this start point.
      for (int i = start + 1; i < end; i++) {
        final LatLng point = route[i];
        final double px = point.longitude * lonToMeters;
        final double py = point.latitude * latToMeters;

        final double pdx = px - startX;
        final double pdy = py - startY;

        // Standard Euclidean distance squared.
        final double distSq = pdx * pdx + pdy * pdy;

        if (distSq > maxDistSq) {
          maxDistSq = distSq;
          maxIndex = i;
        }
      }
    }

    // 4. Splitting the segment.
    // If the furthest point found is greater than our tolerance, it's a critical vertex.
    if (maxDistSq > epsilonSq) {
      // Mark this point to be preserved in the final output.
      preserved[maxIndex] = 1;
      preservedCount++; // Increment our count of preserved points!

      // Grow the stack dynamically if needed.
      if (stackSize + 2 >= stack.length) {
        stack.addAll(List<({int s, int e})>.filled(stack.length, (s: 0, e: 0)));
      }

      // Split the current segment at the maxIndex and push both new segments to the stack.
      stack[stackSize++] = (s: maxIndex, e: end);
      stack[stackSize++] = (s: start, e: maxIndex);
    }
  }

// 5. Final Assembly.
  // Allocate exact memory for the result list using our precise preservedCount.
  final List<LatLng> res = List<LatLng>.filled(preservedCount, route[0]);

  int j = 0;
  if (mapping == null) {
    for (int i = 0; i < preserved.length; i++) {
      if (preserved[i] == 1) {
        res[j] = route[i];
        j++;
      }
    }
    return res;
  }
  for (int i = 0; i < preserved.length; i++) {
    if (preserved[i] == 1) {
      res[j] = route[i];
      mapping[j] = i;
      j++;
    }
  }

  return res;
}