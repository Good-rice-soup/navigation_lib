// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:math';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

class PolylineUtil {
  double _laneWidth = 1;
  static const double metersPerDegree = 111195.0797343687;

  double get getLaneWidth => _laneWidth;

  set setLaneWidth(double laneWidth){
    _laneWidth = laneWidth;
  }

  // Основная функция для упрощения маршрута
  List<LatLng> simplifyRoutePoints(List<LatLng> points, double tolerance) {
    if (points.length < 3) return points; // Не упрощаем менее 3 точек

    // Этап 1: Предобработка — сокращение количества точек через прямоугольники
    List<LatLng> reducedPoints = _reducePointsByRectangles(points);

    // Этап 2: Основное упрощение через итеративную обработку
    return _simplifyByRectangles(reducedPoints, tolerance);
  }

  // Этап 1: Предобработка через прямоугольники
  List<LatLng> _reducePointsByRectangles(List<LatLng> points) {
    List<LatLng> reducedPoints = [];
    int currentIndex = 0;
    reducedPoints.add(points[currentIndex]);

    while (currentIndex < points.length - 1) {
      int nextIndex = currentIndex + 1;
      while (nextIndex < points.length &&
          _isPointInLane(points[nextIndex],
              _createLane(points[currentIndex], points[nextIndex]))) {
        nextIndex++;
      }
      reducedPoints
          .add(points[nextIndex - 1]); // Добавляем последнюю не попавшую точку
      currentIndex = nextIndex - 1; // Переходим к следующей проверке
    }

    if (reducedPoints.last != points.last) {
      reducedPoints
          .add(points.last); // Убедимся, что последняя точка всегда включена
    }

    return reducedPoints;
  }

  // Этап 2: Итеративная реализация упрощения с использованием прямоугольников
  List<LatLng> _simplifyByRectangles(List<LatLng> points, double tolerance) {
    List<bool> keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;

    List<List<int>> stack = [];
    stack.add([0, points.length - 1]);

    while (stack.isNotEmpty) {
      final segment = stack.removeLast();
      final int start = segment[0];
      final int end = segment[1];

      List<LatLng> lane = _createLane(points[start], points[end]);
      double maxDistance = -1.0;
      int maxIndex = start;

      for (int i = start + 1; i < end; i++) {
        if (!_isPointInLane(points[i], lane)) {
          final double dist =
          _pointToLineDistance(points[i], points[start], points[end]);
          if (dist > maxDistance) {
            maxDistance = dist;
            maxIndex = i;
          }
        }
      }

      if (maxDistance > tolerance) {
        keep[maxIndex] = true;
        stack.add([start, maxIndex]);
        stack.add([maxIndex, end]);
      }
    }

    List<LatLng> result = [];
    for (int i = 0; i < points.length; i++) {
      if (keep[i]) {
        result.add(points[i]);
      }
    }
    return result;
  }

  List<LatLng> _createLane(LatLng start, LatLng end) {
    final double deltaLng = end.longitude - start.longitude;
    final double deltaLat = end.latitude - start.latitude;
    final double length = math.sqrt(deltaLng * deltaLng + deltaLat * deltaLat);

    // Converting lane width to degrees
    final double lngNormal = -(deltaLat / length) *
        metersToLongitudeDegrees(_laneWidth, start.latitude);
    final double latNormal =
        (deltaLng / length) * metersToLatitudeDegrees(_laneWidth);

    // Converting lane extension to degrees
    final LatLng extendedStart = LatLng(
        start.latitude -
            (deltaLat / length) * metersToLatitudeDegrees(_laneExtension),
        start.longitude -
            (deltaLng / length) *
                metersToLongitudeDegrees(_laneExtension, start.latitude));
    final LatLng extendedEnd = LatLng(
        end.latitude +
            (deltaLat / length) * metersToLatitudeDegrees(_laneExtension),
        end.longitude +
            (deltaLng / length) *
                metersToLongitudeDegrees(_laneExtension, end.latitude));

    return [
      LatLng(
          extendedEnd.latitude + latNormal, extendedEnd.longitude + lngNormal),
      LatLng(
          extendedEnd.latitude - latNormal, extendedEnd.longitude - lngNormal),
      LatLng(extendedStart.latitude - latNormal,
          extendedStart.longitude - lngNormal),
      LatLng(extendedStart.latitude + latNormal,
          extendedStart.longitude + lngNormal),
    ];
  }

  // Проверка, находится ли точка внутри прямоугольника
  bool _isPointInLane(LatLng point, List<LatLng> lane) {
    int intersections = 0;
    for (int i = 0; i < lane.length; i++) {
      final LatLng a = lane[i];
      final LatLng b = lane[(i + 1) % lane.length];
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

  /// Convert meters to latitude degrees.
  static double metersToLatitudeDegrees(double meters) {
    return meters / metersPerDegree;
  }

  /// Convert meters to longitude degrees using latitude.
  static double metersToLongitudeDegrees(double meters, double latitude) {
    return meters / (metersPerDegree * math.cos(toRadians(latitude)));
  }

  // Вычисление перпендикулярного расстояния от точки до линии
  double _pointToLineDistance(LatLng point, LatLng start, LatLng end) {
    final double dx = end.longitude - start.longitude;
    final double dy = end.latitude - start.latitude;
    if (dx == 0 && dy == 0) {
      return 0.0; // Если start и end совпадают
    }
    return ((point.longitude - start.longitude) * dy -
        (point.latitude - start.latitude) * dx)
        .abs() /
        sqrt(dx * dx + dy * dy);
  }
}
