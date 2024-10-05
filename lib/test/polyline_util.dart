// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:math' as math;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

class Segment {
  Segment(this.startIndex, this.endIndex);

  int startIndex;
  int endIndex;
}

class PolylineUtil {
  static double _laneWidth = 1;
  static const double metersPerDegree = 111195.0797343687;

  double get getLaneWidth => _laneWidth;

  set setLaneWidth(double laneWidth) {
    _laneWidth = laneWidth;
  }

  /// Degrees to radians.
  static double toRadians(double deg) {
    return deg * (math.pi / 180);
  }

  /// Radians to degrees.
  static double toDegrees(double rad) {
    return rad * (180 / math.pi);
  }

  // Основная функция для упрощения маршрута
  static List<LatLng> simplifyRoutePoints(
    List<LatLng> points,
    double tolerance,
  ) {
    if (points.length < 3) {
      return points;
    }
    final List<LatLng> reducedPoints = reducePointsByRectangles(points);
    return simplifyByRectangles(reducedPoints, tolerance);
  }

  // Этап 1: Предобработка — сокращение количества точек через прямоугольники
  static List<LatLng> reducePointsByRectangles(List<LatLng> points) {
    final List<LatLng> reducedPoints = [];
    int currentIndex = 0;
    reducedPoints.add(points[currentIndex]);
    final listLen = points.length;
    List<LatLng> currLane = _createExtendedLane(points[0], points[1]);

    while (currentIndex < listLen - 1) {
      int nextInd = currentIndex + 1;
      while (nextInd < listLen && _isPointInLane(points[nextInd], currLane)) {
        nextInd++;
      }

      reducedPoints.add(points[nextInd - 1]);
      currentIndex = nextInd - 1;
      if (nextInd < points.length) {
        currLane = _createLane(points[currentIndex], points[nextInd]);
      }
    }
    if (reducedPoints.last != points.last) {
      reducedPoints.add(points.last);
    }
    return reducedPoints;
  }

  // Этап 2: Основной этап - итеративная реализация упрощения с использованием прямоугольников
  static List<LatLng> simplifyByRectangles(
    List<LatLng> points,
    double tolerance,
  ) {
    final List<Segment> stack = [Segment(0, points.length - 1)];
    final List<LatLng> result = [points[0]];

    while (stack.isNotEmpty) {
      final Segment segment = stack.removeLast();
      final int start = segment.startIndex;
      final int end = segment.endIndex;

      final List<LatLng> lane = _createLane(points[start], points[end]);
      double maxDistance = -double.infinity;
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
        result.add(points[maxIndex]);
        stack
          ..add(Segment(start, maxIndex))
          ..add(Segment(maxIndex, end));
      }
    }
    result.add(points[points.length - 1]);
    return result;
  }

  static List<LatLng> _createLane(LatLng start, LatLng end) {
    final double deltaLng = end.longitude - start.longitude;
    final double deltaLat = end.latitude - start.latitude;
    final double length = math.sqrt(deltaLng * deltaLng + deltaLat * deltaLat);

    // Converting lane width to degrees
    final double lngNormal = -(deltaLat / length) *
        metersToLongitudeDegrees(_laneWidth, start.latitude);
    final double latNormal =
        (deltaLng / length) * metersToLatitudeDegrees(_laneWidth);

    return [
      LatLng(end.latitude + latNormal, end.longitude + lngNormal),
      LatLng(end.latitude - latNormal, end.longitude - lngNormal),
      LatLng(start.latitude - latNormal, start.longitude - lngNormal),
      LatLng(start.latitude + latNormal, start.longitude + lngNormal),
    ];
  }

  static List<LatLng> _createExtendedLane(LatLng start, LatLng end) {
    const double extension = 1000; // 1000 meters
    final double deltaLng = end.longitude - start.longitude;
    final double deltaLat = end.latitude - start.latitude;
    final double length = math.sqrt(deltaLng * deltaLng + deltaLat * deltaLat);

    final double latN = deltaLat / length;
    final double lngN = deltaLng / length;

    // Converting lane width to degrees
    final double lngNormal =
        -latN * metersToLongitudeDegrees(_laneWidth, start.latitude);
    final double latNormal = lngN * metersToLatitudeDegrees(_laneWidth);

    // Converting lane extension to degrees
    final LatLng extEnd = LatLng(
      end.latitude + latN * metersToLatitudeDegrees(extension),
      end.longitude + lngN * metersToLongitudeDegrees(extension, end.latitude),
    );

    return [
      LatLng(extEnd.latitude + latNormal, extEnd.longitude + lngNormal),
      LatLng(extEnd.latitude - latNormal, extEnd.longitude - lngNormal),
      LatLng(start.latitude - latNormal, start.longitude - lngNormal),
      LatLng(start.latitude + latNormal, start.longitude + lngNormal),
    ];
  }

  // Проверка, находится ли точка внутри прямоугольника
  static bool _isPointInLane(LatLng point, List<LatLng> lane) {
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
  static double _pointToLineDistance(LatLng point, LatLng start, LatLng end) {
    final double dx = end.longitude - start.longitude;
    final double dy = end.latitude - start.latitude;
    if (dx == 0 && dy == 0) {
      return 0.0; // Если start и end совпадают
    }
    final double lineLen = math.sqrt(dx * dx + dy * dy);
    final double numerator = ((point.longitude - start.longitude) * dy -
            (point.latitude - start.latitude) * dx)
        .abs();
    return numerator / lineLen;
  }
}
