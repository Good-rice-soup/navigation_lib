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
    print('[GeoUtils:RouteSimplifier] update route managers');
    final Iterable<int> keys = _zoomToManager.keys;
    for (final int key in keys) {
      _zoomToManager[key]!.updateCurrentLocation(currentLocation);
    }
    originalRouteRouteManager.updateCurrentLocation(currentLocation);
    print(
        '[GeoUtils:RouteSimplifier] originalRouteRouteManager next point index: ${originalRouteRouteManager.nextRoutePointIndex}');
  }

  @Deprecated('Use [getRoute]')
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
    int replaceByOriginalRouteIfLessThan = 200, //later
  }) {
    final ZoomToFactor currentZoomConfig = config.getConfigForZoom(zoom);
    final double tolerance = currentZoomConfig.routeSimplificationFactor;
    final RouteManagerCore currentZoomRouteManager = _zoomToManager[zoom]!;
    final LatLngBounds expandedBounds =
        expandBounds(bounds, currentZoomConfig.boundsExpansionFactor);

    int startingPointIndex = 0;
    List<LatLng> resultRoute = [];

    print('[GeoUtils:RouteSimplifier]');
    print('[GeoUtils:RouteSimplifier] getRoute start');
    //print('[GeoUtils:RouteSimplifier] bounds: $bounds');
    //print('[GeoUtils:RouteSimplifier] expanded bounds: $expandedBounds');
    //cutting stage
    if (currentLocation != null) {
      if (currentZoomConfig.isUseOriginalRouteInVisibleArea) {
        print('[GeoUtils:RouteSimplifier] start DETAILING cutting');
        _updateRouteManagers(currentLocation: currentLocation);
        startingPointIndex = currentZoomRouteManager.nextRoutePointIndex - 1;
        print('[GeoUtils:RouteSimplifier] startingPointIndex: $startingPointIndex');
        resultRoute
            .addAll(currentZoomRouteManager.route.sublist(startingPointIndex));
        print('[GeoUtils:RouteSimplifier] zoom route length: ${currentZoomRouteManager.route.length}');
        print('[GeoUtils:RouteSimplifier] cutted route length: ${resultRoute.length}');
        print('[GeoUtils:RouteSimplifier] end DETAILING cutting');
        /*
        for (int i = 0; i < 100; i++){
          print(resultRoute[i]);
        }

         */
      } else {
        print('[GeoUtils:RouteSimplifier] start NO DETAILING cutting');
        _updateRouteManagers(currentLocation: currentLocation);
        startingPointIndex = currentZoomRouteManager.nextRoutePointIndex;
        resultRoute
          ..add(currentLocation)
          ..addAll(currentZoomRouteManager.route.sublist(startingPointIndex));
        print('[GeoUtils:RouteSimplifier] end NO DETAILING cutting');
      }
    } else {
      print('[GeoUtils:RouteSimplifier] no cutting');
      resultRoute = currentZoomRouteManager.route;
    }

    //detailing stage
    if (currentZoomConfig.isUseOriginalRouteInVisibleArea) {
      print('[GeoUtils:RouteSimplifier] start detailing');
      resultRoute = _detailRoute1(
        resultRoute,
        expandedBounds,
        tolerance,
        startingPointIndex,
        currentLocation,
      );
      print('[GeoUtils:RouteSimplifier] end detailing');
    } else {
      print('[GeoUtils:RouteSimplifier] no detailing');
    }
    /*
    for (final LatLng point in resultRoute){
      print(point);
    }

     */

    print('[GeoUtils:RouteSimplifier] getRoute end');
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
      print('[GeoUtils:RouteSimplifier] detailing NOT CUTTED route');
      return _detailing_1_1(route, bounds, tolerance, indexExtension);
    } else {
      print('[GeoUtils:RouteSimplifier] detailing CUTTED route');
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

    print('[GeoUtils:RouteSimplifier] route length: ${route.length}');
    print('[GeoUtils:RouteSimplifier] bounds: $bounds');
    int i = 0;
    for (final LatLng point in route) {
      if (bounds.contains(point)) {
        if (insideBounds == false) replacementsList.add(i + indexExtension);
        print('[GeoUtils:RouteSimplifier] in bounds: $i - $point');
        print(
            '[GeoUtils:RouteSimplifier] in bounds with extension: ${i + indexExtension}');
        insideBounds = true;
      } else {
        if (insideBounds == true) replacementsList.add(i + indexExtension);
        insideBounds = false;
      }
      i++;
    }

    if (replacementsList.isEmpty) {
      print('[GeoUtils:RouteSimplifier] replacementsList is empty');
      return route;
    } else if (replacementsList.length.isOdd) {
      print('[GeoUtils:RouteSimplifier] odd case of replacementsList');
      replacementsList.add(route.length - 1 + indexExtension);
    }
    print('[GeoUtils:RouteSimplifier] part before bounds added');
    resultPath.addAll(route.sublist(0, replacementsList[0]));
    print('[GeoUtils:RouteSimplifier] resultPath length: ${resultPath.length}');

    print('[GeoUtils:RouteSimplifier] replacementsList: $replacementsList');
    replacementsList =
        _segmentConnecter(replacementsList, route, indexExtension);
    print(
        '[GeoUtils:RouteSimplifier] updated replacementsList: $replacementsList');
    print('[GeoUtils:RouteSimplifier] step in replacements loop');
    for (int i = 0; i < (replacementsList.length - 1); i += 2) {
      print('[GeoUtils:RouteSimplifier] iterator: $i');
      final int startPointIndex = replacementsList[i];
      final int endPointIndex = replacementsList[i + 1];
      print(
          '[GeoUtils:RouteSimplifier] route s/e: $startPointIndex/$endPointIndex');
      final int startPointIndexInOriginalRoute = mapping[startPointIndex]!;
      final int endPointIndexInOriginalRoute = mapping[endPointIndex]!;
      print(
          '[GeoUtils:RouteSimplifier] original route s/e: $startPointIndexInOriginalRoute/$endPointIndexInOriginalRoute');

      final List<LatLng> detailedRoutePart = _route.sublist(
          startPointIndexInOriginalRoute, endPointIndexInOriginalRoute);
      print(
          '[GeoUtils:RouteSimplifier] detailedRoutePart length: ${detailedRoutePart.length}');
      resultPath.addAll(detailedRoutePart);
      print(
          '[GeoUtils:RouteSimplifier] resultPath length: ${resultPath.length}');

      if (i + 1 < replacementsList.length - 1) {
        final List<LatLng> intermediateRoutePart =
            route.sublist(endPointIndex, replacementsList[i + 2]);
        print(
            '[GeoUtils:RouteSimplifier] intermediateRoutePart length: ${intermediateRoutePart.length}');
        resultPath.addAll(intermediateRoutePart);
        print(
            '[GeoUtils:RouteSimplifier] resultPath length: ${resultPath.length}');
      }
    }

    final List<LatLng> lastRoutePart = route.sublist(replacementsList.last);
    print(
        '[GeoUtils:RouteSimplifier] lastRoutePart length: ${lastRoutePart.length}');
    resultPath.addAll(lastRoutePart);
    print('[GeoUtils:RouteSimplifier] resultPath length: ${resultPath.length}');

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
    /*
    for (int i = 0; i < 100; i++){
      print('$i - ${mapping[i]}');
    }

     */
    final List<LatLng> resultPath = [];
    bool insideBounds = false;
    //содержит пары входа и выхода из области видимости function
    // проверяется по четности нечетности количества элементов в списке
    List<int> replacementsList = [0, 1];

    //print('[GeoUtils:RouteSimplifier] route length: ${route.length}');
    //print('[GeoUtils:RouteSimplifier] bounds: $bounds');
    int i = 2;
    for (final LatLng point in route) {
      if (bounds.contains(point)) {
        if (insideBounds == false) replacementsList.add(i);
        //print('[GeoUtils:RouteSimplifier] in bounds: $i - $point');
        //print('[GeoUtils:RouteSimplifier] in bounds with extension: ${i + indexExtension}');
        insideBounds = true;
      } else {
        if (insideBounds == true) replacementsList.add(i);
        insideBounds = false;
      }
      i++;
    }

    if (replacementsList.isEmpty) {
      print('[GeoUtils:RouteSimplifier] replacementsList is empty');
      return route;
    } else if (replacementsList.length.isOdd) {
      print('[GeoUtils:RouteSimplifier] odd case of replacementsList');
      replacementsList.add(route.length - 1);
    }

    print('[GeoUtils:RouteSimplifier] replacementsList: $replacementsList');
    replacementsList =
        _segmentConnecter(replacementsList, route, indexExtension);
    print(
        '[GeoUtils:RouteSimplifier] updated replacementsList: $replacementsList');
    print('[GeoUtils:RouteSimplifier] step in replacements loop');
    for (int i = 0; i < (replacementsList.length - 1); i += 2) {
      print('[GeoUtils:RouteSimplifier] iterator: $i');
      final int startPointIndex = replacementsList[i];
      final int endPointIndex = replacementsList[i + 1];
      print(
          '[GeoUtils:RouteSimplifier] route s/e: $startPointIndex/$endPointIndex');
      final int startPointIndexInOriginalRoute = mapping[startPointIndex + indexExtension]!;
      final int endPointIndexInOriginalRoute = mapping[endPointIndex + indexExtension]!;
      print(
          '[GeoUtils:RouteSimplifier] original route s/e: $startPointIndexInOriginalRoute/$endPointIndexInOriginalRoute');

      if (i == 0) {
        print('[GeoUtils:RouteSimplifier] start detailing cutted part');
        final int index = originalRouteRouteManager.nextRoutePointIndex;
        print('[GeoUtils:RouteSimplifier] cutted detailing index: $index');
        resultPath.addAll(_route.sublist(index, endPointIndexInOriginalRoute));
        print('[GeoUtils:RouteSimplifier] end detailing cutted part');
      } else {
        final List<LatLng> detailedRoutePart = _route.sublist(
            startPointIndexInOriginalRoute, endPointIndexInOriginalRoute);
        print(
            '[GeoUtils:RouteSimplifier] detailedRoutePart length: ${detailedRoutePart.length}');
        resultPath.addAll(detailedRoutePart);
        print(
            '[GeoUtils:RouteSimplifier] resultPath length: ${resultPath.length}');
      }

      if (i + 2 < replacementsList.length) {
        print(
            '[GeoUtils:RouteSimplifier] intermediateRoutePart s/e: $endPointIndex/${replacementsList[i+2]}');
        print(
            '[GeoUtils:RouteSimplifier] intermediateRoutePart original s/e: ${mapping[endPointIndex]}/${mapping[replacementsList[i+2]]}');
        final List<LatLng> intermediateRoutePart =
            route.sublist(endPointIndex, replacementsList[i + 2]);
        print(
            '[GeoUtils:RouteSimplifier] intermediateRoutePart length: ${intermediateRoutePart.length}');
        resultPath.addAll(intermediateRoutePart);
        print(
            '[GeoUtils:RouteSimplifier] resultPath length: ${resultPath.length}');
      }
    }

    final List<LatLng> lastRoutePart = route.sublist(replacementsList.last);
    print(
        '[GeoUtils:RouteSimplifier] lastRoutePart length: ${lastRoutePart.length}');
    resultPath.addAll(lastRoutePart);
    print('[GeoUtils:RouteSimplifier] resultPath length: ${resultPath.length}');

    print('[GeoUtils:RouteSimplifier] resultPath: $resultPath');
    return resultPath;
  }

  List<int> _segmentConnecter(
    List<int> list,
    List<LatLng> route,
    int indexExtension,
  ) {
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
        print(
            '[GeoUtils:RouteSimplifier] closing point coordinates: ${route[a - indexExtension]}');
        print('[GeoUtils:RouteSimplifier] removed opening point: $b');
        print(
            '[GeoUtils:RouteSimplifier] opening point coordinates: ${route[b - indexExtension]}');
      }
    }
    newList.add(list.last);
    return newList;
  }

  bool isPointWithinBounds(LatLngBounds bounds, LatLng? point) {
    const double epsilon = 1e-9;

    if (point == null) return false;

    // Проверка широты
    final bool isLatInBounds =
        (bounds.southwest.latitude - epsilon <= point.latitude) &&
            (point.latitude <= bounds.northeast.latitude + epsilon);

    // Проверка долготы
    bool isLngInBounds;
    if (bounds.southwest.longitude <= bounds.northeast.longitude) {
      isLngInBounds =
          (bounds.southwest.longitude - epsilon <= point.longitude) &&
              (point.longitude <= bounds.northeast.longitude + epsilon);
    } else {
      // Случай пересечения линии смены дат
      isLngInBounds = point.longitude >= bounds.southwest.longitude - epsilon ||
          point.longitude <= bounds.northeast.longitude + epsilon;
    }

    return isLatInBounds && isLngInBounds;
  }
}

/*
[
LatLng(34.21414, -83.5296), ... начало детализации первого сегмента
LatLng(34.21483, -83.52863),
LatLng(34.21528, -83.528),
LatLng(34.21559, -83.52758),
LatLng(34.2162, -83.52674), ... конец детализации первого сегмента
LatLng(34.22356, -83.51288), ... начало промежуточного сегмента
LatLng(34.22436, -83.51119),
LatLng(34.22736, -83.5046),
LatLng(34.22765, -83.50392),/////////////1
LatLng(34.22973, -83.49937),/////////////2
LatLng(34.23025, -83.49832),/////////////3
LatLng(34.23097, -83.49701),/////////////4
LatLng(34.23151, -83.49621),/////////////5
LatLng(34.23218, -83.49528),/////////////6 ... конец промежуточного сегмента
LatLng(34.22765, -83.50392),/////////////1 ... начало детализации второго сегмента
LatLng(34.22872, -83.50158),
LatLng(34.22958, -83.49971),
LatLng(34.22962, -83.49962),
LatLng(34.22973, -83.49937),/////////////2
LatLng(34.23, -83.49883),
LatLng(34.23016, -83.49852),
LatLng(34.23025, -83.49832),/////////////3
LatLng(34.23043, -83.49799),
LatLng(34.23055, -83.49776),
LatLng(34.23074, -83.49742),
LatLng(34.23097, -83.49701),/////////////4
LatLng(34.23126, -83.49657),
LatLng(34.23151, -83.49621),/////////////5
LatLng(34.23192, -83.49563),
LatLng(34.23218, -83.49528),/////////////6
LatLng(34.23251, -83.49487),
LatLng(34.23285, -83.49446),
LatLng(34.23336, -83.49383),
LatLng(34.23389, -83.49319),
LatLng(34.23425, -83.49276),
LatLng(34.23478, -83.4921),
LatLng(34.23532, -83.49145),
LatLng(34.23586, -83.49078),
LatLng(34.23612, -83.49049),
LatLng(34.23676, -83.4897), ... конец детализации второго сегмента
]

[GeoUtils:RouteSimplifier] getRoute start
[GeoUtils:RouteSimplifier] start DETAILING cutting
[GeoUtils:RouteSimplifier] update route managers
[GeoUtils:RouteSimplifier] originalRouteRouteManager next point index: 12
[GeoUtils:RouteSimplifier] startingPointIndex: 6
[GeoUtils:RouteSimplifier] zoom route length: 2376
[GeoUtils:RouteSimplifier] cutted route length: 2370
[GeoUtils:RouteSimplifier] end DETAILING cutting
[GeoUtils:RouteSimplifier] start detailing
[GeoUtils:RouteSimplifier] detailing CUTTED route
[GeoUtils:RouteSimplifier] mapping length: 2376
[GeoUtils:RouteSimplifier] replacementsList: [6, 7, 16, 24]
[GeoUtils:RouteSimplifier] updated replacementsList: [6, 7, 16, 24]
[GeoUtils:RouteSimplifier] step in replacements loop
[GeoUtils:RouteSimplifier] iterator: 0
[GeoUtils:RouteSimplifier] route s/e: 6/7
[GeoUtils:RouteSimplifier] original route s/e: 11/17
[GeoUtils:RouteSimplifier] start detailing cutted part
[GeoUtils:RouteSimplifier] cutted detailing index: 12
[GeoUtils:RouteSimplifier] end detailing cutted part
[GeoUtils:RouteSimplifier] intermediateRoutePart s/e: 7/16
[GeoUtils:RouteSimplifier] intermediateRoutePart length: 9
[GeoUtils:RouteSimplifier] resultPath length: 14
[GeoUtils:RouteSimplifier] iterator: 2
[GeoUtils:RouteSimplifier] route s/e: 16/24
[GeoUtils:RouteSimplifier] original route s/e: 43/69
[GeoUtils:RouteSimplifier] detailedRoutePart length: 26
[GeoUtils:RouteSimplifier] resultPath length: 40
[GeoUtils:RouteSimplifier] lastRoutePart length: 2346
[GeoUtils:RouteSimplifier] resultPath length: 40
[GeoUtils:RouteSimplifier] end detailing
[GeoUtils:RouteSimplifier] getRoute end
*/

/*
[GeoUtils:RouteSimplifier]
[GeoUtils:RouteSimplifier] getRoute start
[GeoUtils:RouteSimplifier] start DETAILING cutting
[GeoUtils:RouteSimplifier] update route managers
[GeoUtils:RouteSimplifier] originalRouteRouteManager next point index: 13
[GeoUtils:RouteSimplifier] startingPointIndex: 6
[GeoUtils:RouteSimplifier] zoom route length: 2380
[GeoUtils:RouteSimplifier] cutted route length: 2374
[GeoUtils:RouteSimplifier] end DETAILING cutting
[GeoUtils:RouteSimplifier] start detailing
[GeoUtils:RouteSimplifier] detailing CUTTED route
[GeoUtils:RouteSimplifier] mapping length: 2380
[GeoUtils:RouteSimplifier] replacementsList: [6, 7, 16, 21]
[GeoUtils:RouteSimplifier] updated replacementsList: [6, 7, 16, 21]
[GeoUtils:RouteSimplifier] step in replacements loop
[GeoUtils:RouteSimplifier] iterator: 0
[GeoUtils:RouteSimplifier] route s/e: 6/7
[GeoUtils:RouteSimplifier] original route s/e: 11/17
[GeoUtils:RouteSimplifier] start detailing cutted part
[GeoUtils:RouteSimplifier] cutted detailing index: 13
[GeoUtils:RouteSimplifier] end detailing cutted part
[GeoUtils:RouteSimplifier] intermediateRoutePart s/e: 7/16
[GeoUtils:RouteSimplifier] intermediateRoutePart original s/e: 17/43
[GeoUtils:RouteSimplifier] intermediateRoutePart length: 9
[GeoUtils:RouteSimplifier] resultPath length: 13
[GeoUtils:RouteSimplifier] iterator: 2
[GeoUtils:RouteSimplifier] route s/e: 16/21
[GeoUtils:RouteSimplifier] original route s/e: 43/58
[GeoUtils:RouteSimplifier] detailedRoutePart length: 15
[GeoUtils:RouteSimplifier] resultPath length: 28
[GeoUtils:RouteSimplifier] lastRoutePart length: 2353
[GeoUtils:RouteSimplifier] resultPath length: 28
[GeoUtils:RouteSimplifier] end detailing
[GeoUtils:RouteSimplifier] getRoute end

route with bug
[
LatLng(34.21483, -83.52863), ... начало детализации первого сегмента
LatLng(34.21528, -83.528),
LatLng(34.21559, -83.52758),
LatLng(34.2162, -83.52674), ... конец детализации первого сегмента
LatLng(34.22356, -83.51288), ... начало промежуточного сегмента
LatLng(34.22436, -83.51119),
LatLng(34.22736, -83.5046),
LatLng(34.22765, -83.50392), /// 1
LatLng(34.22973, -83.49937), /// 2
LatLng(34.23025, -83.49832), /// 3
LatLng(34.23097, -83.49701), /// 4
LatLng(34.23151, -83.49621), /// 5
LatLng(34.23218, -83.49528), ... конец промежуточного сегмента
LatLng(34.22765, -83.50392), /// 1 ... начало детализации второго сегмента
LatLng(34.22872, -83.50158),
LatLng(34.22958, -83.49971),
LatLng(34.22962, -83.49962),
LatLng(34.22973, -83.49937), /// 2
LatLng(34.23, -83.49883),
LatLng(34.23016, -83.49852),
LatLng(34.23025, -83.49832), /// 3
LatLng(34.23043, -83.49799),
LatLng(34.23055, -83.49776),
LatLng(34.23074, -83.49742),
LatLng(34.23097, -83.49701), /// 4
LatLng(34.23126, -83.49657),
LatLng(34.23151, -83.49621), /// 5
LatLng(34.23192, -83.49563), ... конец детализации второго сегмента
]

cutted zoom route
[
LatLng(34.21376, -83.53012),
LatLng(34.21656, -83.52624),
LatLng(34.21697, -83.52564),
LatLng(34.21746, -83.52487),
LatLng(34.21796, -83.52398),
LatLng(34.21949, -83.52092),
LatLng(34.22257, -83.51487), ... начало пути
LatLng(34.22356, -83.51288), ... начало промежуточного сегмента
LatLng(34.22436, -83.51119),
LatLng(34.22736, -83.5046),
LatLng(34.22765, -83.50392), /// 1
LatLng(34.22973, -83.49937), /// 2
LatLng(34.23025, -83.49832), /// 3
LatLng(34.23097, -83.49701), /// 4
LatLng(34.23151, -83.49621), /// 5
LatLng(34.23218, -83.49528), ... конец пути (не включён)
LatLng(34.23586, -83.49078),
LatLng(34.23612, -83.49049),
LatLng(34.23741, -83.48891),
LatLng(34.23956, -83.48625),
LatLng(34.24122, -83.48423),
LatLng(34.24183, -83.48346),
LatLng(34.24411, -83.4807),
LatLng(34.24513, -83.47941),
LatLng(34.24581, -83.47851),
LatLng(34.24655, -83.47745),
LatLng(34.24753, -83.47595),
LatLng(34.24813, -83.47497),
LatLng(34.2491, -83.47324),
LatLng(34.24982, -83.4719),
LatLng(34.25135, -83.46914),
LatLng(34.25217, -83.46769),
LatLng(34.25318, -83.46584),
LatLng(34.25347, -83.46475),
LatLng(34.25354, -83.46434),
LatLng(34.25372, -83.46301),
LatLng(34.25384, -83.46254),
LatLng(34.25513, -83.46319),
LatLng(34.25597, -83.46357),
LatLng(34.25689, -83.46406),
LatLng(34.25889, -83.46503),
LatLng(34.26046, -83.46582),
LatLng(34.26181, -83.46646),
LatLng(34.26226, -83.46665),
LatLng(34.26273, -83.46689),
LatLng(34.26373, -83.46749),
LatLng(34.26503, -83.46837),
LatLng(34.26563, -83.46875),
LatLng(34.26607, -83.46893),
LatLng(34.26635, -83.46901),
LatLng(34.26661, -83.46906),
LatLng(34.26696, -83.46907),
LatLng(34.26736, -83.46902),
LatLng(34.26781, -83.46889),
LatLng(34.26812, -83.46875),
LatLng(34.26829, -83.46865),
LatLng(34.26876, -83.46832),
LatLng(34.27099, -83.46655),
LatLng(34.27136, -83.46628),
LatLng(34.27174, -83.46604),
LatLng(34.27194, -83.46594),
LatLng(34.27258, -83.46569),
LatLng(34.27306, -83.4656),
LatLng(34.27606, -83.46514),
LatLng(34.27819, -83.46479),
LatLng(34.27854, -83.46476),
LatLng(34.2789, -83.46478),
LatLng(34.27926, -83.46484),
LatLng(34.28253, -83.46578),
LatLng(34.28306, -83.46595),
LatLng(34.28397, -83.46631),
LatLng(34.28431, -83.46646),
LatLng(34.28496, -83.46678),
LatLng(34.28608, -83.46738),
LatLng(34.28756, -83.46822),
LatLng(34.29296, -83.47121),
LatLng(34.29568, -83.47273),
LatLng(34.29667, -83.4733),
LatLng(34.29782, -83.47391),
LatLng(34.30158, -83.47601),
LatLng(34.30225, -83.47634),
LatLng(34.30289, -83.47662),
LatLng(34.30324, -83.47675),
LatLng(34.30415, -83.47705),
LatLng(34.30478, -83.47722),
LatLng(34.30534, -83.47733),
LatLng(34.30602, -83.47744),
LatLng(34.30677, -83.47752),
LatLng(34.30753, -83.47755),
LatLng(34.30859, -83.47751),
LatLng(34.30918, -83.47745),
LatLng(34.31012, -83.4773),
LatLng(34.3109, -83.47712),
LatLng(34.31194, -83.47679),
LatLng(34.31274, -83.47647),
LatLng(34.31359, -83.47605),
LatLng(34.3145, -83.47554),
LatLng(34.3149, -83.47528),
LatLng(34.3153, -83.47501),
LatLng(34.31606, -83.47442),
]

mapping
0 - 0
1 - 2
2 - 5
3 - 6
4 - 9
5 - 10
6 - 11
7 - 17
8 - 18
9 - 19
10 - 21
11 - 24
12 - 29
13 - 31
14 - 33
15 - 42
16 - 43
17 - 47
18 - 50
19 - 54
20 - 56
21 - 58
22 - 66
23 - 67
24 - 69
25 - 73
26 - 76
27 - 77
28 - 83
29 - 87
30 - 89
31 - 91
32 - 94
33 - 96
34 - 99
35 - 101
36 - 103
37 - 106
38 - 110
39 - 115
40 - 117
41 - 123
42 - 126
43 - 130
44 - 132
45 - 140
46 - 148
47 - 152
48 - 158
49 - 160
50 - 161
51 - 163
52 - 165
53 - 168
54 - 172
55 - 174
56 - 176
57 - 179
58 - 182
59 - 186
60 - 189
61 - 190
62 - 192
63 - 199
64 - 201
65 - 203
66 - 204
67 - 205
68 - 206
69 - 211
70 - 216
71 - 217
72 - 218
73 - 219
74 - 224
75 - 225
76 - 228
77 - 229
78 - 232
79 - 235
80 - 238
81 - 243
82 - 246
83 - 247
84 - 250
85 - 253
86 - 254
87 - 255
88 - 256
89 - 257
90 - 258
91 - 259
92 - 260
93 - 261
94 - 262
95 - 265
96 - 266
97 - 268
98 - 272
99 - 274
*/