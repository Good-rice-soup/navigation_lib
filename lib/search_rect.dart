import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';

class SearchRect {
  SearchRect({
    required LatLng start,
    required LatLng end,
    double rectWidth = 10,
    double rectExtension = 5,
  }) {
    segmentVector = (
      start.latitude - end.latitude,
      start.longitude - end.longitude,
    );

    final double lngDiff = end.longitude - start.longitude;
    final double latDiff = end.latitude - start.latitude;
    final double len = sqrt(lngDiff * lngDiff + latDiff * latDiff);

    // Converting rect width to degrees to make latitude and longitude normal
    final double lngNorm =
        -(latDiff / len) * metersToLngDegrees(rectWidth, start.latitude);
    final double latNorm = (lngDiff / len) * metersToLatDegrees(rectWidth);

    // Converting rect extension to degrees to make extended start and end
    final LatLng extStart = LatLng(
      start.latitude - (latDiff / len) * metersToLatDegrees(rectExtension),
      start.longitude -
          (lngDiff / len) * metersToLngDegrees(rectExtension, start.latitude),
    );
    final LatLng extEnd = LatLng(
      end.latitude + (latDiff / len) * metersToLatDegrees(rectExtension),
      end.longitude +
          (lngDiff / len) * metersToLngDegrees(rectExtension, end.latitude),
    );

    rect = [
      LatLng(extEnd.latitude + latNorm, extEnd.longitude + lngNorm),
      LatLng(extEnd.latitude - latNorm, extEnd.longitude - lngNorm),
      LatLng(extStart.latitude - latNorm, extStart.longitude - lngNorm),
      LatLng(extStart.latitude + latNorm, extStart.longitude + lngNorm),
    ];
  }

  List<LatLng> rect = [];
  (double, double) segmentVector = (0, 0);
}
