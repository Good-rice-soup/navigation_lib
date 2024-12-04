//import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';
import 'route_manager_core.dart';

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

class PolylineSimplifier {
  PolylineSimplifier({
    required List<LatLng> route,
    required this.configSet,
  }) {
    _route = RouteManagerCore.checkRouteForDuplications(route);
    _generate();

    originalRouteRouteManager = RouteManagerCore(
      route: _route,
      laneWidth: laneWidth,
      laneExtension: laneExtension,
    );
  }

  final double laneWidth = 10;
  final double laneExtension = 5;

  static const double metersPerDegree = 111195.0797343687;

  List<LatLng> _route = [];
  late final RouteManagerCore originalRouteRouteManager;
  final Set<ZoomToFactor> configSet;
  late final RouteSimplificationConfig config =
      RouteSimplificationConfig(config: configSet);
  final Map<double, Map<int, int>> _toleranceToMappedZoomRoutes = {};

  final Map<int, RouteManagerCore> _zoomToManager = {};

  void _mapIndices(
    List<LatLng> originalPath,
    List<LatLng> simplifiedPath,
    double tolerance,
  ) {
    final Map<int, int> mapping = {};
    int simplifiedIndex = 0;

    for (int originalIndex = 0;
        originalIndex < originalPath.length;
        originalIndex++) {
      if (simplifiedPath[simplifiedIndex] == originalPath[originalIndex]) {
        mapping[simplifiedIndex] = originalIndex;
        simplifiedIndex++;

        if (simplifiedIndex >= simplifiedPath.length) break;
      }
    }
    _toleranceToMappedZoomRoutes[tolerance] = mapping;
  }

  void _generate() {
    final Map<int, double> zoomToTolerance = {};
    final Map<double, RouteManagerCore> toleranceToManager = {};

    for (final zoomToFactor in config.config) {
      zoomToTolerance[zoomToFactor.zoom] =
          zoomToFactor.routeSimplificationFactor;
    }

    final Set<double> tolerances = zoomToTolerance.values.toSet();
    for (final tolerance in tolerances) {
      final List<LatLng> simplifiedRoute;
      simplifiedRoute = PolylineUtil.simplifyRoutePoints(
        points: _route,
        tolerance: tolerance,
      );
      toleranceToManager[tolerance] = RouteManagerCore(
        route: simplifiedRoute,
        laneWidth: laneWidth,
        laneExtension: laneExtension,
      );
      _mapIndices(_route, simplifiedRoute, tolerance);
    }

    final Iterable<int> zooms = zoomToTolerance.keys;
    for (final zoom in zooms) {
      _zoomToManager[zoom] = toleranceToManager[zoomToTolerance[zoom]]!;
    }
  }

  void _updateRouteManagers({required LatLng currentLocation}) {
    final Iterable<int> keys = _zoomToManager.keys;
    for (final int key in keys) {
      _zoomToManager[key]!.updateCurrentLocation(currentLocation);
    }
    originalRouteRouteManager.updateCurrentLocation(currentLocation);
  }

  @Deprecated('Use [getRoute]')
  List<LatLng> getRoute3({
    required LatLngBounds bounds,
    required int zoom,
    LatLng? currentLocation,
    int replaceByOriginalRouteIfLessThan = 200,
  }) {
    final ZoomToFactor currentZoomConfig = config.getConfigForZoom(zoom);
    final double tolerance = currentZoomConfig.routeSimplificationFactor;
    final List<LatLng> currentZoomRoute = _zoomToManager[zoom]!.route;
    final LatLngBounds expandedBounds =
        expandBounds(bounds, currentZoomConfig.boundsExpansionFactor);

    if (currentZoomRoute.isEmpty) return [];

    if (currentZoomConfig.isUseOriginalRouteInVisibleArea) {
      final List<LatLng> detailedRoute =
          _detailRoute(currentZoomRoute, expandedBounds, tolerance);
      if (currentLocation != null) {
        final List<LatLng> cuttedDetailedRoute = [currentLocation];
        _updateRouteManagers(currentLocation: currentLocation);

        final int originalRouteNextRoutePointIndex =
            originalRouteRouteManager.nextRoutePointIndex;

        final int amountOfPointsToFinish =
            _route.length - originalRouteNextRoutePointIndex;
        if (amountOfPointsToFinish <= replaceByOriginalRouteIfLessThan) {
          cuttedDetailedRoute
              .addAll(_route.sublist(originalRouteNextRoutePointIndex));
          return cuttedDetailedRoute;
        }

        if (expandedBounds.contains(currentLocation)) {
          final LatLng originalRouteNextRoutePoint =
              originalRouteRouteManager.nextRoutePoint;
          final int index = detailedRoute.indexOf(originalRouteNextRoutePoint);
          cuttedDetailedRoute.addAll(detailedRoute.sublist(index));
          //TODO: придумать что-то получше, чем indexOf()
        } else {
          final int currentZoomNextRoutePointIndex =
              _zoomToManager[zoom]!.nextRoutePointIndex;
          cuttedDetailedRoute.addAll(detailedRoute.sublist(
              currentZoomNextRoutePointIndex)); //////////////////////////////////////////////////////
          //индекс следующей точки передаётся не в путь зумроута, а в ДЕТАЛИЗИРОВАННЫЙ путь
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
          _zoomToManager[zoom]!.nextRoutePointIndex;
      cuttedCurrentZoomRoute
          .addAll(currentZoomRoute.sublist(currentZoomNextRoutePointIndex));
      return cuttedCurrentZoomRoute;
    }
    return currentZoomRoute;
  }

  List<LatLng> _detailRoute(
    List<LatLng> zoomRoute,
    LatLngBounds bounds,
    double tolerance,
  ) {
    final Map<int, int> mapping = _toleranceToMappedZoomRoutes[tolerance]!;
    final List<LatLng> resultPath = [];
    bool insideBounds = false;
    //содержит пары входа и выхода из области видимости
    // проверяется по четности нечетности количества элементов в списке
    final List<int> listOfReplacements = [];

    int i = 0;
    for (final LatLng point in zoomRoute) {
      if (bounds.contains(point)) {
        if (insideBounds == false) listOfReplacements.add(i);
        insideBounds = true;
      } else {
        if (insideBounds == true) listOfReplacements.add(i);
        insideBounds = false;
      }
      i++;
    }

    //на случай если конец пути покрыт зоной видимости, предыдущий цикл не
    // закроет пару замены пути. но при этом надо сделать проверку на дубликаты
    if (listOfReplacements.length.isOdd) {
      listOfReplacements.add(zoomRoute.length - 1);
    }

    if (listOfReplacements.isEmpty) return zoomRoute;

    resultPath.addAll(zoomRoute.sublist(0, listOfReplacements[0]));
    for (int i = 0; i < (listOfReplacements.length - 1); i += 2) {
      final int startPointIndex = listOfReplacements[i];
      final int endPointIndex = listOfReplacements[i + 1];
      final int startPointIndexInOriginalRoute = mapping[startPointIndex]!;
      final int endPointIndexInOriginalRoute = mapping[endPointIndex]!;
      final List<LatLng> detailedRoutePart = _route.sublist(
          startPointIndexInOriginalRoute, endPointIndexInOriginalRoute);
      if (resultPath.isEmpty) {
      }
      resultPath.addAll(detailedRoutePart);

      if (i + 1 < listOfReplacements.length - 1) {
        final List<LatLng> intermediateRoutePart =
            zoomRoute.sublist(endPointIndex, listOfReplacements[i + 2]);
        resultPath.addAll(intermediateRoutePart);
      }
    }

    final List<LatLng> lastRoutePart =
        zoomRoute.sublist(listOfReplacements.last);
    resultPath.addAll(lastRoutePart);
    if (resultPath.last == resultPath[resultPath.length - 2]) {
      resultPath.removeAt(resultPath.length - 1);
    }
    return resultPath;
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

  List<LatLng> getRoute({
    required LatLngBounds bounds,
    required int zoom,
    LatLng? currentLocation,
  }) {
    final ZoomToFactor currentZoomConfig = config.getConfigForZoom(zoom);
    final double tolerance = currentZoomConfig.routeSimplificationFactor;
    final RouteManagerCore currentZoomRouteManager = _zoomToManager[zoom]!;
    final LatLngBounds expandedBounds =
        expandBounds(bounds, currentZoomConfig.boundsExpansionFactor);

    int startingPointIndex = 0;
    List<LatLng> resultRoute = [];

    //cutting stage
    if (currentLocation != null) {
      if (currentZoomConfig.isUseOriginalRouteInVisibleArea) {
        _updateRouteManagers(currentLocation: currentLocation);
        startingPointIndex = currentZoomRouteManager.nextRoutePointIndex - 1;
        resultRoute
            .addAll(currentZoomRouteManager.route.sublist(startingPointIndex));
      } else {
        _updateRouteManagers(currentLocation: currentLocation);
        startingPointIndex = currentZoomRouteManager.nextRoutePointIndex;
        resultRoute
          ..add(currentLocation)
          ..addAll(currentZoomRouteManager.route.sublist(startingPointIndex));
      }
    } else {
      resultRoute = currentZoomRouteManager.route;
    }

    //detailing stage
    if (currentZoomConfig.isUseOriginalRouteInVisibleArea) {
      resultRoute = _detailRoute1(
        resultRoute,
        expandedBounds,
        tolerance,
        startingPointIndex,
        currentLocation,
      );
    }

    return resultRoute;
  }

  List<LatLng> _detailRoute1(
    List<LatLng> route,
    LatLngBounds bounds,
    double tolerance,
    int indexExtension,
    LatLng? currentLocation,
  ) {
    final bool isNull = currentLocation == null;
    if (isNull) {
      return _detailing_1_1(route, bounds, tolerance, indexExtension);
    } else {
      return _detailing_1_2(
          route, bounds, tolerance, indexExtension, currentLocation);
    }
  }

  List<LatLng> _detailing_1_1(
    List<LatLng> route,
    LatLngBounds bounds,
    double tolerance,
    int indexExtension,
  ) {
    final Map<int, int> mapping = _toleranceToMappedZoomRoutes[tolerance]!;
    final List<LatLng> resultPath = [];
    bool insideBounds = false;
    //содержит пары входа и выхода из области видимости
    // проверяется по четности нечетности количества элементов в списке
    List<int> replacementsList = [];

    int i = 0;
    for (final LatLng point in route) {
      if (bounds.contains(point)) {
        if (insideBounds == false) replacementsList.add(i + indexExtension);
        insideBounds = true;
      } else {
        if (insideBounds == true) replacementsList.add(i + indexExtension);
        insideBounds = false;
      }
      i++;
    }

    if (replacementsList.isEmpty) {
      return route;
    } else if (replacementsList.length.isOdd) {
      replacementsList.add(route.length - 1 + indexExtension);
    }
    resultPath.addAll(route.sublist(0, replacementsList[0]));
    replacementsList = _segmentConnector(replacementsList);
    for (int i = 0; i < (replacementsList.length - 1); i += 2) {
      final int startPointIndex = replacementsList[i];
      final int endPointIndex = replacementsList[i + 1];
      final int startPointIndexInOriginalRoute = mapping[startPointIndex]!;
      final int endPointIndexInOriginalRoute = mapping[endPointIndex]!;

      final List<LatLng> detailedRoutePart = _route.sublist(
          startPointIndexInOriginalRoute, endPointIndexInOriginalRoute);
      resultPath.addAll(detailedRoutePart);

      if (i + 1 < replacementsList.length - 1) {
        final List<LatLng> intermediateRoutePart =
            route.sublist(endPointIndex, replacementsList[i + 2]);
        resultPath.addAll(intermediateRoutePart);
      }
    }

    final List<LatLng> lastRoutePart = route.sublist(replacementsList.last);
    resultPath.addAll(lastRoutePart);

    return resultPath;
  }

  List<LatLng> _detailing_1_2(
    List<LatLng> route,
    LatLngBounds bounds,
    double tolerance,
    int indexExtension,
    LatLng currentLocation,
  ) {
    final Map<int, int> mapping = _toleranceToMappedZoomRoutes[tolerance]!;
    print('[GeoUtils:RouteSimplifier] mapping length: ${mapping.length}');
    final List<LatLng> resultPath = [];
    bool insideBounds = false;
    //содержит пары входа и выхода из области видимости function
    // проверяется по четности нечетности количества элементов в списке
    List<int> replacementsList = [0, 1];

    int i = 2;
    for (final LatLng point in route) {
      if (bounds.contains(point)) {
        if (insideBounds == false) replacementsList.add(i);
        insideBounds = true;
      } else {
        if (insideBounds == true) replacementsList.add(i);
        insideBounds = false;
      }
      i++;
    }

    if (replacementsList.isEmpty) {
      return route;
    } else if (replacementsList.length.isOdd) {
      replacementsList.add(route.length - 1);
    }

    replacementsList = _segmentConnector(replacementsList);
    for (int i = 0; i < (replacementsList.length - 1); i += 2) {
      final int startPointIndex = replacementsList[i];
      final int endPointIndex = replacementsList[i + 1];
      final int startPointIndexInOriginalRoute =
          mapping[startPointIndex + indexExtension]!;
      final int endPointIndexInOriginalRoute =
          mapping[endPointIndex + indexExtension]!;

      if (i == 0) {
        final int index = originalRouteRouteManager.nextRoutePointIndex;
        resultPath.addAll(_route.sublist(index, endPointIndexInOriginalRoute));
      } else {
        final List<LatLng> detailedRoutePart = _route.sublist(
            startPointIndexInOriginalRoute, endPointIndexInOriginalRoute);
        resultPath.addAll(detailedRoutePart);
      }

      if (i + 2 < replacementsList.length) {
        final List<LatLng> intermediateRoutePart =
            route.sublist(endPointIndex, replacementsList[i + 2]);
        resultPath.addAll(intermediateRoutePart);
      }
    }

    final List<LatLng> lastRoutePart = route.sublist(replacementsList.last);
    resultPath.addAll(lastRoutePart);

    return resultPath;
  }

  List<int> _segmentConnector(List<int> list) {
    final List<int> newList = [list.first];
    for (int i = 1; i < list.length - 1; i += 2) {
      final int a = list[i];
      final int b = list[i + 1];
      //b > a always
      if (b - a != 1) {
        newList
          ..add(a)
          ..add(b);
      } else {
        print('[GeoUtils:RouteSimplifier] removed closing point: $a');
        print('[GeoUtils:RouteSimplifier] removed opening point: $b');
      }
    }
    newList.add(list.last);
    return newList;
  }
}
