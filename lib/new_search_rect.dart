import 'dart:math';
import 'dart:typed_data';

import 'geo_utils.dart';

/// Zero-cost абстракция над плоским массивом Float64List.
/// Формат блока для 1 сегмента (10 double):
/// [0] normX, [1] normY
/// [2] a.lat, [3] a.lng
/// [4] b.lat, [5] b.lng
/// [6] c.lat, [7] c.lng
/// [8] d.lat, [9] d.lng
extension type SearchRectBuffer(Float64List buffer) {

  /// Выделяет память: количество сегментов * 10
  SearchRectBuffer.allocate(int segmentsCount)
      : buffer = Float64List(segmentsCount * 10);

  void calculateAndSet(
      int segmentIndex,
      double startLat, double startLng,
      double endLat, double endLng,
      double rectWidth, double rectExt,
      ) {
    final int offset = segmentIndex * 10;

    final double dx = endLat - startLat;
    final double dy = endLng - startLng;
    final double inversedLen = 1.0 / sqrt(dx * dx + dy * dy);

    // Оптимизация: совмещаем нормализацию и преобразование метров в градусы
    final double normX = dx * inversedLen;
    final double normY = dy * inversedLen;

    // Записываем нормали
    buffer[offset] = normX;
    buffer[offset + 1] = normY;

    // Превращаем градусы в радианы
    final double cosStart = cos(startLat * constantPiDividedBy180);
    final double cosEnd = cos(endLat * constantPiDividedBy180);

    // Ширина и расширение в градусах (lat всегда meters/111111)
    final double latWidth = rectWidth / metersPerDegree;
    final double latExt = rectExt / metersPerDegree;

    // Векторы расширения (оптимизация: убраны промежуточные переменные)
    final double smt1 = normX * latExt;
    final double smt2 = normY * rectExt / metersPerDegree;
    final double endExtX = endLat + smt1;
    final double endExtY = endLng + smt2 * cosEnd;
    final double startExtX = startLat - smt1;
    final double startExtY = startLng - smt2 * cosStart;

    // Нормаль (перпендикуляр) без лишних операций
    final double smt3 = normX * rectWidth / metersPerDegree;
    final double perpX = normY * latWidth;
    final double perpYStart = -smt3 * cosStart;
    final double perpYEnd = -smt3 * cosEnd;

    // Записываем координаты углов
    buffer[offset + 2] = endExtX + perpX;
    buffer[offset + 3] = endExtY + perpYEnd;
    buffer[offset + 4] = endExtX - perpX;
    buffer[offset + 5] = endExtY - perpYEnd;
    buffer[offset + 6] = startExtX - perpX;
    buffer[offset + 7] = startExtY - perpYStart;
    buffer[offset + 8] = startExtX + perpX;
    buffer[offset + 9] = startExtY + perpYStart;
  }

  (double, double) getNormalisedSegmVect(int segmentIndex) {
    final int offset = segmentIndex * 10;
    return (buffer[offset], buffer[offset + 1]);
  }

  bool isPointInRect(int segmentIndex, double pLat, double pLng) {
    final int offset = (segmentIndex * 10) + 2;
    int intersections = 0;

    for (int i = 0; i < 4; i++) {
      final int idxA = offset + (i * 2);
      final int idxB = offset + (((i + 1) % 4) * 2);

      final double aLat = buffer[idxA];
      final double aLng = buffer[idxA + 1];
      final double bLat = buffer[idxB];
      final double bLng = buffer[idxB + 1];

      if ((aLng > pLng) != (bLng > pLng)) {
        final double intersect = (bLat - aLat) * (pLng - aLng) /
            (bLng - aLng) + aLat;
        if (pLat > intersect) intersections++;
      }
    }
    return intersections.isOdd;
  }
}