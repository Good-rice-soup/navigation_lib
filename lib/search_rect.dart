import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';

class SearchRect {
  SearchRect({
    required LatLng start,
    required LatLng end,
    double rectWidth = 10,
    double rectExt = 5,
  }) {
    final double dx = end.latitude - start.latitude;
    final double dy = end.longitude - start.longitude;
    final double inversedLen = 1.0 / sqrt(dx * dx + dy * dy);

    // Оптимизация: совмещаем нормализацию и преобразование метров в градусы
    final double normX = dx * inversedLen;
    final double normY = dy * inversedLen;
    normalisedSegmVect = (normX, normY);

    final double cosStart = cos(toRadians(start.latitude));
    final double cosEnd = cos(toRadians(end.latitude));

    // Ширина и расширение в градусах (lat всегда meters/111111)
    final double latWidth = rectWidth / metersPerDegree;
    final double latExt = rectExt / metersPerDegree;

    // Векторы расширения (оптимизация: убраны промежуточные переменные)
    final double smt1 = normX * latExt;
    final double smt2 = normY * rectExt / metersPerDegree;
    final double endExtX = end.latitude + smt1;
    final double endExtY = end.longitude + smt2 * cosEnd;
    final double startExtX = start.latitude - smt1;
    final double startExtY = start.longitude - smt2 * cosStart;

    // Нормаль (перпендикуляр) без лишних операций
    final double smt3 = normX * rectWidth / metersPerDegree;
    final double perpX = normY * latWidth;
    final double perpYStart = -smt3 * cosStart;
    final double perpYEnd = -smt3 * cosEnd;

    rect = [
      LatLng(endExtX + perpX, endExtY + perpYEnd),
      LatLng(endExtX - perpX, endExtY - perpYEnd),
      LatLng(startExtX - perpX, startExtY - perpYStart),
      LatLng(startExtX + perpX, startExtY + perpYStart),
    ];
  }

  SearchRect.copy({required this.rect, required this.normalisedSegmVect});

  List<LatLng> rect = [];

  late (double, double) normalisedSegmVect;

  bool isPointInRect(LatLng point) {
    int intersections = 0;
    for (int i = 0; i < rect.length; i++) {
      final LatLng a = rect[i];
      final LatLng b = rect[(i + 1) % rect.length];
      if ((a.longitude > point.longitude) != (b.longitude > point.longitude)) {
        final double intersect = (b.latitude - a.latitude) *
                (point.longitude - a.longitude) /
                (b.longitude - a.longitude) +
            a.latitude;
        if (point.latitude > intersect) {
          intersections++;
        }
      }
    }
    return intersections.isOdd;
  }
}
