import 'dart:math';
import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';

//mapping - simplified ind to orig ind
List<LatLng> rdpRouteSimplifier(
  List<LatLng> route,
  double toleranceInM, {
  int ignoreIfLess = 300,
  Map<int, int>? mapping,
}) {
  if (route.length < 2 || toleranceInM <= 0 || route.length <= ignoreIfLess) {
    return List<LatLng>.from(route);
  }

  final double epsilonSq = toleranceInM * toleranceInM;
  final Uint8List preserved = Uint8List(route.length);
  final List<({int s, int e})> stack =
      List<({int s, int e})>.filled(128, (s: 0, e: 0));
  int stackSize = 1;
  stack[0] = (s: 0, e: route.length - 1);
  preserved[0] = 1;
  preserved[route.length - 1] = 1;

  while (stackSize > 0) {
    final (:s, :e) = stack[--stackSize];
    final int start = s;
    final int end = e;
    final LatLng startPoint = route[start];
    final LatLng endPoint = route[end];

    final double avgLat = (startPoint.latitude + endPoint.latitude) / 2;
    final double lonToMeters = cos(toRadians(avgLat)) * metersPerDegree;
    const double latToMeters = metersPerDegree;

    final double startX = startPoint.longitude * lonToMeters;
    final double startY = startPoint.latitude * latToMeters;
    final double endX = endPoint.longitude * lonToMeters;
    final double endY = endPoint.latitude * latToMeters;

    final double dx = endX - startX;
    final double dy = endY - startY;

    double maxDistSq = 0.0;
    int maxIndex = start;

    if (dx != 0.0 || dy != 0.0) {
      final double invDenominator = 1.0 / (dx * dx + dy * dy);
      for (int i = start + 1; i < end; i++) {
        final LatLng point = route[i];
        final double px = point.longitude * lonToMeters;
        final double py = point.latitude * latToMeters;

        final double numerator = (px - startX) * dy - (py - startY) * dx;
        final double distSq = numerator * numerator * invDenominator;

        if (distSq > maxDistSq) {
          maxDistSq = distSq;
          maxIndex = i;
          if (distSq >= epsilonSq) break;
        }
      }
    }

    if (maxDistSq > epsilonSq) {
      preserved[maxIndex] = 1;
      if (stackSize + 2 >= stack.length) {
        stack.addAll(List<({int s, int e})>.filled(stack.length, (s: 0, e: 0)));
      }
      stack[stackSize++] = (s: maxIndex, e: end);
      stack[stackSize++] = (s: start, e: maxIndex);
    }
  }

  if (mapping == null) {
    return [
      for (int i = 0; i < preserved.length; i++)
        if (preserved[i] == 1) route[i]
    ];
  }

  int j = 0;
  final List<LatLng> res = [];
  for (int i = 0; i < preserved.length; i++) {
    if (preserved[i] == 1) {
      res.add(route[i]);
      mapping[j] = i;
      j++;
    }
  }
  return res;
}
