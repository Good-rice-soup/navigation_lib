// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:math';
import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';

List<LatLng> rdpRouteSimplifier(
  List<LatLng> route,
  double toleranceInM, [
  int ignoreIfLess = 300,
]) {
  if (route.length < 2 || toleranceInM <= 0 || route.length <= ignoreIfLess) {
    return route;
  }
  final double epsilonSq = toleranceInM * toleranceInM;

  final Uint8List preserved = Uint8List(route.length);
  final List<({int s, int e})> stack =
      List<({int s, int e})>.generate(64, (_) => (s: 0, e: 0));

  int stackSize = 1;
  stack[0] = (s: 0, e: route.length - 1);
  preserved[0] = 1;
  preserved[route.length - 1] = 1;

  while (stackSize > 0) {
    final ({int s, int e}) range = stack[--stackSize];
    final int start = range.s;
    final int end = range.e;
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

    for (int i = start + 1; i < end; i++) {
      final double distSq;
      if (dx == 0 && dy == 0) {
        distSq = 0;
      } else {
        final LatLng point = route[i];
        final double pointX = point.longitude * lonToMeters;
        final double pointY = point.latitude * latToMeters;

        final double numerator =
            (pointX - startX) * dy - (pointY - startY) * dx;
        distSq = (numerator * numerator) / (dx * dx + dy * dy);
      }

      if (distSq > maxDistSq) {
        maxDistSq = distSq;
        maxIndex = i;
        if (maxDistSq > epsilonSq) break;
      }
    }

    if (maxDistSq > epsilonSq) {
      preserved[maxIndex] = 1;
      if (stackSize + 2 >= stack.length) {
        stack.addAll([(s: 0, e: 0), (s: 0, e: 0)]);
      }
      stack[stackSize++] = (s: maxIndex, e: end);
      stack[stackSize++] = (s: start, e: maxIndex);
    }
  }

  return [
    for (int i = 0; i < preserved.length; i++)
      if (preserved[i] == 1) route[i]
  ];
}
