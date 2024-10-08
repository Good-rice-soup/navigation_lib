import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'polyline_util.dart';
/*
zoom level	tile side size at equator
0	          40,075 km
1	          20,037.5 km
2	          10,018.75 km
3	          5,009.38 km
4	          2,504.69 km
5	          1,252.34 km
6	          626.17 km
7	          313.08 km
8	          156.54 km
9	          78.27 km
10	        39.13 km
11	        19.57 km
12	        9.78 km
13	        4.89 km
14	        2.44 km
15	        1.22 km
16	        610 m
17	        305 m
18	        152 m
19	        76 m
20	        38 m
21	        19 m

21 - 20 - original route
19 and less - tolerance = metersToDegrees((tileSideSize) * 0.01)
*/

@immutable
class ZoomToFactor {
  const ZoomToFactor({
    this.isUseOriginalRouteInVisibleArea = false,
    this.boundsExpansionFactor = 1,
    required this.zoom,
    required this.routeSimplificationFactor,
  });

  final int zoom;
  final double routeSimplificationFactor;
  final double boundsExpansionFactor;
  final bool isUseOriginalRouteInVisibleArea;
}

class RouteSimplificationConfig {
  RouteSimplificationConfig({required this.config});

  final Set<ZoomToFactor> config;

  ZoomToFactor getConfigForZoom(int zoom) {
    return config.firstWhere((zoomFactor) => zoomFactor.zoom == zoom);
  }
}

@immutable
class PolylineSimplifier {
  PolylineSimplifier({required this.route, required this.configSet}) {
    _generateRoutesForZooms();
  }

  static const Map<int, int> zoomSizes = {
    0: 40075000,
    1: 20037500,
    2: 10018750,
    3: 5009380,
    4: 2504690,
    5: 1252340,
    6: 626170,
    7: 313080,
    8: 156540,
    9: 78270,
    10: 39130,
    11: 19570,
    12: 9780,
    13: 4890,
    14: 2440,
    15: 1220,
    16: 610,
    17: 305,
    18: 152,
    19: 76,
    20: 38,
    21: 19,
  };

  static const double metersPerDegree = 111195.0797343687;

  final List<LatLng> route;
  final Set<ZoomToFactor> configSet;
  late final RouteSimplificationConfig config =
      RouteSimplificationConfig(config: configSet);

  // Хеш-таблица для хранения маршрутов, где ключ - зум
  late final Map<int, List<LatLng>> _routesByZoom = {};

  void _generateRoutesForZooms() {
    for (final zoomFactor in config.config) {
      final List<LatLng> simplifiedRoute;
      if (zoomFactor.zoom < 20) {
        final double tolerance = zoomFactor.routeSimplificationFactor;
        simplifiedRoute = PolylineUtil.simplifyRoutePoints(
          points: route,
          tolerance: tolerance,
        );
      } else {
        simplifiedRoute = route;
      }
      _routesByZoom[zoomFactor.zoom] = simplifiedRoute;
    }
  }

  double generateTolerance({required int zoom}) {
    final int tileSize = zoomSizes[zoom]!;
    return (tileSize * 0.01) / metersPerDegree;
  }

  bool isPointAfterStart(LatLng start, LatLng end, LatLng point) {
    // Вычисляем векторы для отрезков start->end и start->point
    final double vectorSELat = end.latitude - start.latitude;
    final double vectorSELng = end.longitude - start.longitude;

    final double vectorSPLat = point.latitude - start.latitude;
    final double vectorSPLng = point.longitude - start.longitude;

    final double dotProduct =
        vectorSELat * vectorSPLat + vectorSELng * vectorSPLng;

    // Если скалярное произведение положительное, точка находится после старта
    return dotProduct > 0;
  }

  /// Метод для получения маршрута с учётом текущего положения и разбивки отрезков
  List<LatLng> getRoute({
    required LatLngBounds bounds,
    required int zoom,
    LatLng? currentLocation,
    bool shouldCutPastPath = false,
  }) {
    final ZoomToFactor zoomConfig = config.getConfigForZoom(zoom);
    final List<LatLng>? zoomRoute = _routesByZoom[zoom];

    if (zoomRoute == null) {
      return [];
    }

    final LatLngBounds expandedBounds =
        _expandBounds(bounds, zoomConfig.boundsExpansionFactor);

    final List<LatLng> visibleRoute = zoomRoute.where((point) {
      return _isPointInBounds(point, expandedBounds);
    }).toList();

    if (visibleRoute.isEmpty) {
      return [];
    }

    if (!shouldCutPastPath) {
      return visibleRoute;
    } else {
      LatLng? nearestPoint;
      LatLng? secondNearestPoint;
      double minDistance = double.infinity;
      double secondMinDistance = double.infinity;

      if (currentLocation == null) {
        return [];
      }

      for (final point in visibleRoute) {
        final double distance = _calculateDistance(point, currentLocation);
        if (distance < minDistance) {
          secondNearestPoint = nearestPoint;
          secondMinDistance = minDistance;
          nearestPoint = point;
          minDistance = distance;
        } else if (distance < secondMinDistance) {
          secondNearestPoint = point;
          secondMinDistance = distance;
        }
      }

      if (nearestPoint == null || secondNearestPoint == null) {
        return [];
      }

      // 1. Добавляем текущее местоположение в итоговый маршрут
      final List<LatLng> resultRoute = [currentLocation];

      LatLng finalPoint;
      final bool isAfter = isPointAfterStart(
          nearestPoint,
          visibleRoute[visibleRoute.indexOf(nearestPoint) + 1],
          currentLocation);
      if (visibleRoute.indexOf(nearestPoint) < (visibleRoute.length + 1)) {
        if (isAfter) {
          finalPoint = visibleRoute[visibleRoute.indexOf(nearestPoint) + 1];
        } else {
          finalPoint = nearestPoint;
        }
      } else {
        finalPoint = nearestPoint;
      }

      resultRoute.add(finalPoint);

      // 4. Обрезаем оставшийся видимый маршрут
      final int startIndex = visibleRoute.indexOf(finalPoint);
      final List<LatLng> remainingRoute = visibleRoute.sublist(startIndex + 1);

      resultRoute.addAll(remainingRoute);

      return resultRoute;
    }
  }

  static List<LatLng> interpolatePoints(LatLng p1, LatLng p2, int numPoints) {
    final List<LatLng> interpolatedPoints = [];
    for (int i = 1; i <= numPoints; i++) {
      final double fraction = i / (numPoints + 1);
      final double lat = p1.latitude + (p2.latitude - p1.latitude) * fraction;
      final double lng =
          p1.longitude + (p2.longitude - p1.longitude) * fraction;
      interpolatedPoints.add(LatLng(lat, lng));
    }
    return interpolatedPoints;
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    const double R = 6371009.0; // Радиус Земли в метрах
    final double lat1 = p1.latitude * (pi / 180);
    final double lat2 = p2.latitude * (pi / 180);
    final double dLat = lat2 - lat1;
    final double dLng = (p2.longitude - p1.longitude) * (pi / 180);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c; // Возвращает расстояние в метрах
  }

  LatLngBounds _expandBounds(LatLngBounds bounds, double factor) {
    final LatLng southwest = LatLng(
      bounds.southwest.latitude -
          (bounds.southwest.latitude * (factor - 1) / 2),
      bounds.southwest.longitude -
          (bounds.southwest.longitude * (factor - 1) / 2),
    );
    final LatLng northeast = LatLng(
      bounds.northeast.latitude +
          (bounds.northeast.latitude * (factor - 1) / 2),
      bounds.northeast.longitude +
          (bounds.northeast.longitude * (factor - 1) / 2),
    );

    return LatLngBounds(southwest: southwest, northeast: northeast);
  }

  bool _isPointInBounds(LatLng point, LatLngBounds bounds) {
    return point.latitude >= bounds.southwest.latitude &&
        point.latitude <= bounds.northeast.latitude &&
        point.longitude >= bounds.southwest.longitude &&
        point.longitude <= bounds.northeast.longitude;
  }
}

/*
example of using class


void main() {
  const Set<ZoomToFactor> configSet = {
    ZoomToFactor(
      zoom: 10,
      routeSimplificationFactor: 0.00005,
      boundsExpansionFactor: 1.5,
    ),
    ZoomToFactor(
      zoom: 15,
      routeSimplificationFactor: 0.1,
      boundsExpansionFactor: 1.1,
    ),
  };

  RoutePaintHelper(
    configSet: configSet,
    route: const [
      LatLng(0, 0),
      LatLng(1, 1),
      LatLng(2, 2),
    ],
  ).getRoute(
    bounds: LatLngBounds(
      southwest: const LatLng(0, 0),
      northeast: const LatLng(1, 1),
    ),
    zoom: 10,
    currentLocation: const LatLng(0, 0),
  );
}
 */
