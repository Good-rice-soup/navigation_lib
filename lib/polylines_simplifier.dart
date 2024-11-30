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

  List<LatLng> getRoute3({
    required LatLngBounds bounds,
    required int zoom,
    LatLng? currentLocation,
    int replaceByOriginalRouteIfLessThan = 200,
  }) {
    print('[GeoUtils:RouteSimplifier]');
    print('[GeoUtils:RouteSimplifier] getRoute3 start');
    //print('[GeoUtils:RouteSimplifier] original bounds: $bounds');
    final ZoomToFactor currentZoomConfig = config.getConfigForZoom(zoom);
    final double tolerance = currentZoomConfig.routeSimplificationFactor;
    final List<LatLng> currentZoomRoute = _zoomToManager[zoom]!.route;
    final LatLngBounds expandedBounds =
        expandBounds(bounds, currentZoomConfig.boundsExpansionFactor);

    if (currentZoomRoute.isEmpty) return [];

    if (currentZoomConfig.isUseOriginalRouteInVisibleArea) {
      print('[GeoUtils:RouteSimplifier] start detailing');
      print(
          '[GeoUtils:RouteSimplifier] currentZoomRoute length: ${currentZoomRoute.length}');
      final List<LatLng> detailedRoute =
          _detailRoute(currentZoomRoute, expandedBounds, tolerance);
      print(
          '[GeoUtils:RouteSimplifier] detailedRoute length: ${detailedRoute.length}');
      print('[GeoUtils:RouteSimplifier] end detailing');
      if (currentLocation != null) {
        print('[GeoUtils:RouteSimplifier] start cutting');
        final List<LatLng> cuttedDetailedRoute = [currentLocation];
        _updateRouteManagers(currentLocation: currentLocation);

        final int originalRouteNextRoutePointIndex =
            originalRouteRouteManager.nextRoutePointIndex;

        final int amountOfPointsToFinish =
            _route.length - originalRouteNextRoutePointIndex;
        if (amountOfPointsToFinish <= replaceByOriginalRouteIfLessThan) {
          print('[GeoUtils:RouteSimplifier] use simplified cutting');
          cuttedDetailedRoute
              .addAll(_route.sublist(originalRouteNextRoutePointIndex));
          print('[GeoUtils:RouteSimplifier] end cutting');
          print('[GeoUtils:RouteSimplifier] getRoute3 end');
          return cuttedDetailedRoute;
        }

        if (expandedBounds.contains(currentLocation)) {
          print('[GeoUtils:RouteSimplifier] current location in bounds');
          final LatLng originalRouteNextRoutePoint =
              originalRouteRouteManager.nextRoutePoint;
          final int index = detailedRoute.indexOf(originalRouteNextRoutePoint);
          print(
              '[GeoUtils:RouteSimplifier] start cutting index in detailed route by indexOf: $index');
          cuttedDetailedRoute.addAll(detailedRoute.sublist(index));
          //TODO: придумать что-то получше, чем indexOf()
        } else {
          print('[GeoUtils:RouteSimplifier] current location out of bounds');
          final int currentZoomNextRoutePointIndex =
              _zoomToManager[zoom]!.nextRoutePointIndex;
          print(
              '[GeoUtils:RouteSimplifier] currentZoomNextRoutePointIndex: $currentZoomNextRoutePointIndex');
          cuttedDetailedRoute.addAll(detailedRoute.sublist(
              currentZoomNextRoutePointIndex)); //////////////////////////////////////////////////////
          //индекс следующей точки передаётся не в путь зумроута, а в ДЕТАЛИЗИРОВАННЫЙ путь
        }
        print('[GeoUtils:RouteSimplifier] end cutting');
        print('[GeoUtils:RouteSimplifier] getRoute3 end');

        return cuttedDetailedRoute;
      }
      print('[GeoUtils:RouteSimplifier] getRoute3 end');
      return detailedRoute;
    }

    if (currentLocation != null) {
      print('[GeoUtils:RouteSimplifier] start cutting');
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
      print('[GeoUtils:RouteSimplifier] end cutting');
      print('[GeoUtils:RouteSimplifier] getRoute3 end');
      return cuttedCurrentZoomRoute;
    }
    print('[GeoUtils:RouteSimplifier] no detailing, no cutting');
    print('[GeoUtils:RouteSimplifier] getRoute3 end');
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

    //print('[GeoUtils:RouteSimplifier] expanded bounds: $bounds');
    //print('[GeoUtils:RouteSimplifier] zoomRoute: $zoomRoute');

    int i = 0;
    for (final LatLng point in zoomRoute) {
      //print('[GeoUtils:RouteSimplifier] is $point inside: ${bounds.contains(point)}');
      if (bounds.contains(point)) {
        if (insideBounds == false) listOfReplacements.add(i);
        print('[GeoUtils:RouteSimplifier] in bounds: $i');
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
      print(
          '[GeoUtils:RouteSimplifier] odd case additional index: ${zoomRoute.length - 1}');
      listOfReplacements.add(zoomRoute.length - 1);
    }
    print('[GeoUtils:RouteSimplifier] listOfReplacements: $listOfReplacements');

    if (listOfReplacements.isEmpty) return zoomRoute;

    resultPath.addAll(zoomRoute.sublist(0, listOfReplacements[0]));
    print(
        '[GeoUtils:RouteSimplifier] starting resultPath length: ${resultPath.length}');
    print('[GeoUtils:RouteSimplifier] step in replacement cycle');
    for (int i = 0; i < (listOfReplacements.length - 1); i += 2) {
      print('[GeoUtils:RouteSimplifier] iterator: $i');
      final int startPointIndex = listOfReplacements[i];
      final int endPointIndex = listOfReplacements[i + 1];
      print('[GeoUtils:RouteSimplifier] s/e: $startPointIndex/$endPointIndex');
      final int startPointIndexInOriginalRoute = mapping[startPointIndex]!;
      final int endPointIndexInOriginalRoute = mapping[endPointIndex]!;
      print(
          '[GeoUtils:RouteSimplifier] original s/e: $startPointIndexInOriginalRoute/$endPointIndexInOriginalRoute');
      final List<LatLng> detailedRoutePart = _route.sublist(
          startPointIndexInOriginalRoute, endPointIndexInOriginalRoute);
      print(
          '[GeoUtils:RouteSimplifier] detailedRoutePart length: ${detailedRoutePart.length}');
      if (resultPath.isEmpty) {
        print('[GeoUtils:RouteSimplifier] resultPath is empty');
      } else {
        print(
            '[GeoUtils:RouteSimplifier] are the connecting elements same: ${resultPath.last == detailedRoutePart.first}');
      }
      resultPath.addAll(detailedRoutePart);

      if (i + 1 < listOfReplacements.length - 1) {
        print('[GeoUtils:RouteSimplifier] intermediate segment insertion');
        //print('[GeoUtils:RouteSimplifier] zoomRoute length: ${zoomRoute.length}');
        print('[GeoUtils:RouteSimplifier] start: $endPointIndex');
        print('[GeoUtils:RouteSimplifier] end: ${listOfReplacements[i + 2]}');
        final List<LatLng> intermediateRoutePart =
            zoomRoute.sublist(endPointIndex, listOfReplacements[i + 2]);
        print(
            '[GeoUtils:RouteSimplifier] intermediateRoutePart length: ${intermediateRoutePart.length}');
        print(
            '[GeoUtils:RouteSimplifier] are the connecting elements same: ${resultPath.last == intermediateRoutePart.first}');
        resultPath.addAll(intermediateRoutePart);
        print(
            '[GeoUtils:RouteSimplifier] resultPath length: ${resultPath.length}');
      }
    }
    print('[GeoUtils:RouteSimplifier] step out replacement cycle');

    final List<LatLng> lastRoutePart =
        zoomRoute.sublist(listOfReplacements.last);
    print(
        '[GeoUtils:RouteSimplifier] lastRoutePart length: ${lastRoutePart.length}');
    print(
        '[GeoUtils:RouteSimplifier] are the connecting elements same: ${resultPath.last == lastRoutePart.first}');
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
    int replaceByOriginalRouteIfLessThan = 200,
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
      _updateRouteManagers(currentLocation: currentLocation);
      startingPointIndex = currentZoomRouteManager.nextRoutePointIndex - 1;
      resultRoute
        ..add(currentLocation)
        ..addAll(currentZoomRouteManager.route.sublist(startingPointIndex));
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
    final Map<int, int> mapping = _toleranceToMappedZoomRoutes[tolerance]!;
    final List<LatLng> resultPath = [];
    bool insideBounds = false;
    //содержит пары входа и выхода из области видимости
    // проверяется по четности нечетности количества элементов в списке
    final List<int> replacementsList = [];

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

    if (replacementsList.isEmpty) return route;
    if (replacementsList.length.isOdd) {
      replacementsList.add(route.length - 1 + indexExtension);
    }
    if (currentLocation == null) {
      resultPath.addAll(route.sublist(0, replacementsList[0]));
    }

    for (int i = 0; i < (replacementsList.length - 1); i += 2) {
      final int startPointIndex = replacementsList[i];
      final int endPointIndex = replacementsList[i + 1];
      final int startPointIndexInOriginalRoute = mapping[startPointIndex]!;
      final int endPointIndexInOriginalRoute = mapping[endPointIndex]!;

      if (i == 0 && currentLocation != null) {
        final int index = originalRouteRouteManager.nextRoutePointIndex;
        resultPath
          ..add(currentLocation)
          ..addAll(_route.sublist(index, endPointIndexInOriginalRoute));
      } else {
        final List<LatLng> detailedRoutePart = _route.sublist(
            startPointIndexInOriginalRoute, endPointIndexInOriginalRoute);
        resultPath.addAll(detailedRoutePart);
      }

      if (i + 1 < replacementsList.length - 1) {
        final List<LatLng> intermediateRoutePart =
            route.sublist(endPointIndex, replacementsList[i + 2]);
        resultPath.addAll(intermediateRoutePart);
      }
    }

    final List<LatLng> lastRoutePart = route.sublist(replacementsList.last);
    resultPath.addAll(lastRoutePart);
    if (resultPath.last == resultPath[resultPath.length - 2]) {
      resultPath.removeAt(resultPath.length - 1);
    }

    return resultPath;
  }
}
