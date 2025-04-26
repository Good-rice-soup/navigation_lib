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
    segmentVector = ( dx, dy);
    final double inversedLen = 1.0 / sqrt(dx * dx + dy * dy);

    // Оптимизация: совмещаем нормализацию и преобразование метров в градусы
    final double normX = dx * inversedLen;
    final double normY = dy * inversedLen;

    final double cosStart = cos(toRadians(start.latitude));
    final double cosEnd = cos(toRadians(end.latitude));

    // Ширина и расширение в градусах (lat всегда meters/111111)
    final double latWidth = rectWidth / metersPerDegree;
    final double latExt = rectExt / metersPerDegree;

    // Векторы расширения (оптимизация: убраны промежуточные переменные)
    final double endExtX = end.latitude + normX * latExt;
    final double endExtY =
        end.longitude + normY * (rectExt / (metersPerDegree * cosEnd));
    final double startExtX = start.latitude - normX * latExt;
    final double startExtY =
        start.longitude - normY * (rectExt / (metersPerDegree * cosStart));

    // Нормаль (перпендикуляр) без лишних операций
    final double perpX = normY * latWidth;
    final double perpYStart =
        -normX * (rectWidth / (metersPerDegree * cosStart));
    final double perpYEnd = -normX * (rectWidth / (metersPerDegree * cosEnd));

    A = LatLng(endExtX + perpX, endExtY + perpYEnd);
    B = LatLng(endExtX - perpX, endExtY - perpYEnd);
    C = LatLng(startExtX - perpX, startExtY - perpYStart);
    D = LatLng(startExtX + perpX, startExtY + perpYStart);

    // Предвычисленные параметры для isPointInRect
    _abDx = B.latitude - A.latitude;
    _abDy = B.longitude - A.longitude;
    _adDx = D.latitude - A.latitude;
    _adDy = D.longitude - A.longitude;
    _maxAB = _abDx * _abDx + _abDy * _abDy;
    _maxAD = _adDx * _adDx + _adDy * _adDy;
  }

  late final LatLng A, B, C, D;
  late final double _abDx, _abDy, _adDx, _adDy, _maxAB, _maxAD;

  late (double, double) segmentVector;

  bool isPointInRect(LatLng p) {
    final double apX = p.latitude - A.latitude;
    final double apY = p.longitude - A.longitude;

    // Быстрое вычисление проекций без создания объектов
    final double dotAB = apX * _abDx + apY * _abDy;
    final double dotAD = apX * _adDx + apY * _adDy;

    return (dotAB >= 0) &&
        (dotAB <= _maxAB) &&
        (dotAD >= 0) &&
        (dotAD <= _maxAD);
  }
}
