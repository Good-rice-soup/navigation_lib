//import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'config_classes.dart';
import 'new_route_manager.dart';
import 'polyline_util.dart';
import 'route_cutter.dart';

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
class PolylineSimplifier {
  PolylineSimplifier({required this.route, required this.configSet}) {
    _generateRoutesForZooms();
    _generateRouteManagersForZooms();
  }

  final int maxZoomForRepaintRoute = 18;

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
  late final NewRouteManager originalRouteRouteManager;
  final Set<ZoomToFactor> configSet;
  late final RouteSimplificationConfig config =
      RouteSimplificationConfig(config: configSet);

  // Хеш-таблица для хранения маршрутов, где ключ - зум
  final Map<int, List<LatLng>> _routesByZoom = {};
  final Map<int, NewRouteManager> _routeManagersByZoom = {};

  Map<int, List<LatLng>> get routeByZoom => _routesByZoom;

  void _generateRoutesForZooms() {
    double previouseTolerance = 0;
    List<LatLng> previouseRoute = [];
    for (final zoomFactor in config.config) {
      final List<LatLng> simplifiedRoute;
      if (zoomFactor.zoom < 20) {
        final double tolerance = zoomFactor.routeSimplificationFactor;

        if (previouseTolerance == tolerance) {
          simplifiedRoute = previouseRoute;
        } else {
          simplifiedRoute = PolylineUtil.simplifyRoutePoints(
            points: route,
            tolerance: tolerance,
          );
          previouseRoute = simplifiedRoute;
          previouseTolerance = tolerance;
        }
      } else {
        simplifiedRoute = route;
      }
      _routesByZoom[zoomFactor.zoom] = simplifiedRoute;
    }
  }

  void _generateRouteManagersForZooms() {
    final Iterable<int> keys = _routesByZoom.keys;
    for (final int key in keys) {
      _routeManagersByZoom[key] =
          NewRouteManager(route: _routesByZoom[key]!, sidePoints: []);
    }
    originalRouteRouteManager = NewRouteManager(route: route, sidePoints: []);
  }

  void _updateRouteManagers({required LatLng currentLocation}) {
    final Iterable<int> keys = _routeManagersByZoom.keys;
    for (final int key in keys) {
      _routeManagersByZoom[key]!.updateStatesOfSidePoints(currentLocation);
    }
    originalRouteRouteManager.updateStatesOfSidePoints(currentLocation);
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
  @Deprecated('Use [getRoute3]')
  List<LatLng> getRoute({
    required LatLngBounds bounds,
    required int zoom,
    LatLng? currentLocation,
    bool shouldCutPastPath = false,
  }) {
    final ZoomToFactor zoomConfig = config.getConfigForZoom(zoom);
    final List<LatLng>? zoomRoute = _routesByZoom[zoom];

    print('zoomRoute = $zoomRoute -- polylines_simplifier_log');
    if (zoomRoute == null) {
      return [];
    }

    final LatLngBounds expandedBounds =
        expandBounds(bounds, zoomConfig.boundsExpansionFactor);

    print('expandedBounds = $expandedBounds -- polylines_simplifier_log');

    final List<LatLng> visibleRoute = zoomRoute;
    /*final List<LatLng> visibleRoute = [];
    for (final LatLng point in zoomRoute){
      if (_isPointInBounds(point, expandedBounds)){
        visibleRoute.add(point);
      }
    }*/

    print('visibleRoute = $visibleRoute -- polylines_simplifier_log');

    if (visibleRoute.isEmpty) {
      return [];
    }

    if (!shouldCutPastPath) {
      return visibleRoute;
    } else {
      if (currentLocation == null) {
        return [];
      }
      _updateRouteManagers(currentLocation: currentLocation);
      List<LatLng> resultRoute = [currentLocation];
      int pointInd = _routeManagersByZoom[zoom]!.nextRoutePointIndex;

      while (pointInd < visibleRoute.length) {
        resultRoute.add(visibleRoute[pointInd]);
        pointInd++;
      }

      /*
      LatLng? nearestPoint;
      LatLng? secondNearestPoint;
      double minDistance = double.infinity;
      double secondMinDistance = double.infinity;

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

       */

      if (zoomConfig.isUseOriginalRouteInVisibleArea) {
        final RouteCutter cutter = RouteCutter();
        resultRoute = cutter.cutRoute(
          originalRoute: route,
          simplifiedRoute: resultRoute,
          nextPointIndexOnOriginalRoute: pointInd,
          currentLocation: currentLocation,
          bounds: bounds,
          maxZoomForRepaintRoute: maxZoomForRepaintRoute,
          currentZoomLevel: zoom,
        );
      }

      print('resultRoute = $resultRoute -- polylines_simplifier_log');
      return resultRoute;
    }
  }

  /// cuts the route like routeCutter
  @Deprecated('Use [getRoute3]')
  List<LatLng> getRoute2(
      {required LatLngBounds bounds,
      required int zoom,
      LatLng? currentLocation,
      int replaceByOriginalRouteIfLessThan = 200}) {
    final ZoomToFactor currentZoomConfig = config.getConfigForZoom(zoom);
    final List<LatLng>? currentZoomRoute = _routesByZoom[zoom];
    final LatLngBounds expandedBounds =
        expandBounds(bounds, currentZoomConfig.boundsExpansionFactor);

    if (currentZoomRoute == null || currentZoomRoute.isEmpty) {
      return [];
    }
    if (currentLocation == null) {
      return currentZoomRoute;
    }

    _updateRouteManagers(currentLocation: currentLocation);
    final List<LatLng> cuttedCurrentZoomRoute = [currentLocation];
    final int currentZoomNextRoutePointIndex =
        _routeManagersByZoom[zoom]!.nextRoutePointIndex;
    int i = currentZoomNextRoutePointIndex;
    while (i < currentZoomRoute.length) {
      cuttedCurrentZoomRoute.add(currentZoomRoute[i]);
      i++;
    }

    if (currentZoomConfig.isUseOriginalRouteInVisibleArea) {
      final NewRouteManager detailingAssistant =
          NewRouteManager(route: cuttedCurrentZoomRoute, sidePoints: []);
      //it updates with other zooms route managers by current location
      final int startIndex = originalRouteRouteManager.nextRoutePointIndex;
      final List<LatLng> detailedRoute = [currentLocation];
      int cutStartIndex = 0;

      if (route.length - startIndex <= replaceByOriginalRouteIfLessThan) {
        return [
          currentLocation,
          ...route.sublist(startIndex),
        ];
      }
      for (int i = startIndex; i < route.length; i++) {
        final LatLng point = route[i];
        if (expandedBounds.contains(point)) {
          detailingAssistant.updateStatesOfSidePoints(point);
          detailedRoute.add(point);
        } else {
          cutStartIndex = detailingAssistant.nextRoutePointIndex;
          break;
        }
      }

      final List<LatLng> resultRoute = [
        ...detailedRoute,
        ...cuttedCurrentZoomRoute.sublist(cutStartIndex),
      ];

      return resultRoute;
    }
    return cuttedCurrentZoomRoute;
  }

  List<LatLng> getRoute3(
      {required LatLngBounds bounds,
      required int zoom,
      LatLng? currentLocation,
      int replaceByOriginalRouteIfLessThan = 200}) {
    final ZoomToFactor currentZoomConfig = config.getConfigForZoom(zoom);
    final List<LatLng>? currentZoomRoute = _routesByZoom[zoom];
    final LatLngBounds expandedBounds =
        expandBounds(bounds, currentZoomConfig.boundsExpansionFactor);

    if (currentZoomRoute == null || currentZoomRoute.isEmpty) {
      return [];
    }

    if (currentZoomConfig.isUseOriginalRouteInVisibleArea) {
      final List<LatLng> detailedRoute =
          _detailRoute(currentZoomRoute, expandedBounds);
      if (currentLocation != null) {
        final List<LatLng> cuttedDetailedRoute = [currentLocation];
        _updateRouteManagers(currentLocation: currentLocation);

        final int originalRouteNextRoutePointIndex = originalRouteRouteManager.nextRoutePointIndex < route.length - 1 ?
            originalRouteRouteManager.nextRoutePointIndex + 1 : originalRouteRouteManager.nextRoutePointIndex;
        final LatLng originalRouteNextRoutePoint =
        route[originalRouteNextRoutePointIndex];

        /*
        if (originalRouteNextRoutePoint == currentLocation) {
          return cuttedDetailedRoute;
        }
         */

        final int amountOfPointsToFinish =
            route.length - originalRouteNextRoutePointIndex;
        if (amountOfPointsToFinish <= replaceByOriginalRouteIfLessThan) {
          cuttedDetailedRoute
              .addAll(route.sublist(originalRouteNextRoutePointIndex));
          return cuttedDetailedRoute;
        }

        if (expandedBounds.contains(currentLocation)) {
          final int index = detailedRoute.indexOf(originalRouteNextRoutePoint);
          cuttedDetailedRoute.addAll(detailedRoute.sublist(index));
        } else {
          final int currentZoomNextRoutePointIndex =
              _routeManagersByZoom[zoom]!.nextRoutePointIndex;
          cuttedDetailedRoute
              .addAll(detailedRoute.sublist(currentZoomNextRoutePointIndex));
        }

        return cuttedDetailedRoute;
      }
      return detailedRoute;
    }

    if (currentLocation != null) {
      final List<LatLng> cuttedCurrentZoomRoute = [currentLocation];
      _updateRouteManagers(currentLocation: currentLocation);

      final LatLng originalRouteNextRoutePoint =
          originalRouteRouteManager.nextRoutePoint;
      if (originalRouteNextRoutePoint == currentLocation) {
        return cuttedCurrentZoomRoute;
      }

      final int currentZoomNextRoutePointIndex =
          _routeManagersByZoom[zoom]!.nextRoutePointIndex;
      cuttedCurrentZoomRoute
          .addAll(currentZoomRoute.sublist(currentZoomNextRoutePointIndex));

      return cuttedCurrentZoomRoute;
    }
    return currentZoomRoute;
  }

  List<LatLng> _detailRoute(List<LatLng> zoomRoute, LatLngBounds bounds) {
    final List<LatLng> firstPart = [];
    final List<LatLng> secondPart = [];

    int zoomRouteBoundStartIndex = -1;
    LatLng zoomRouteBoundStartPoint = route.first;
    bool isBeforeBounds = true;
    int differenceBetweenStartAndEnd = 0;

    for (final LatLng point in zoomRoute) {
      if (!bounds.contains(point) && isBeforeBounds) {
        firstPart.add(point);
        zoomRouteBoundStartIndex++;
        zoomRouteBoundStartPoint = point;
      } else if (isBeforeBounds && zoomRouteBoundStartIndex == -1) {
        firstPart.add(point);
        zoomRouteBoundStartIndex++;
        zoomRouteBoundStartPoint = point;
        isBeforeBounds = false;
      } else if (bounds.contains(point)) {
        isBeforeBounds = false;
        differenceBetweenStartAndEnd++;
      } else {
        secondPart.add(point);
      }
    }

    //if bounds don't touch the route
    if (isBeforeBounds) return firstPart;

    //if bounds covers the last point
    if (!isBeforeBounds && secondPart.isEmpty) secondPart.add(zoomRoute.last);

    int zoomRouteBoundEndIndex =
        zoomRouteBoundStartIndex + differenceBetweenStartAndEnd + 1;
    if (zoomRouteBoundEndIndex > zoomRoute.length - 1) {
      zoomRouteBoundEndIndex = zoomRoute.length - 1;
    }
    final LatLng zoomRouteBoundEndPoint = zoomRoute[zoomRouteBoundEndIndex];
    final int sublistStart = (zoomRouteBoundStartIndex < zoomRoute.length - 1)
        ? route.indexOf(zoomRouteBoundStartPoint) + 1
        : route.indexOf(zoomRouteBoundStartPoint);
    final int sublistEnd = route.indexOf(zoomRouteBoundEndPoint);

    return [
      ...firstPart,
      ...route.sublist(sublistStart, sublistEnd),
      ...secondPart,
    ];
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

/*
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
   */

  LatLngBounds expandBounds(LatLngBounds bounds, double factor) {
    final double lat =
        (bounds.northeast.latitude - bounds.southwest.latitude).abs();
    final double lng =
        (bounds.northeast.longitude - bounds.southwest.longitude).abs();
    final LatLng southwest = LatLng(
      bounds.southwest.latitude - (lat * (factor - 1) / 2),
      bounds.southwest.longitude - (lng * (factor - 1) / 2),
    );
    final LatLng northeast = LatLng(
      bounds.northeast.latitude + (lat * (factor - 1) / 2),
      bounds.northeast.longitude + (lng * (factor - 1) / 2),
    );

    return LatLngBounds(southwest: southwest, northeast: northeast);
  }

/*
  bool _isPointInBounds(LatLng point, LatLngBounds bounds) {
    return point.latitude >= bounds.southwest.latitude &&
        point.latitude <= bounds.northeast.latitude &&
        point.longitude >= bounds.southwest.longitude &&
        point.longitude <= bounds.northeast.longitude;
  }
   */
}
