//import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';
import 'new_route_manager.dart';

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
    _route = NewRouteManager.checkRouteForDuplications(route);
    _generate();

    originalRouteRouteManager = NewRouteManager(
      route: _route,
      sidePoints: [],
      laneWidth: laneWidth,
      laneExtension: laneExtension,
    );
  }

  final double laneWidth = 10;
  final double laneExtension = 5;

  static const double metersPerDegree = 111195.0797343687;

  List<LatLng> _route = [];
  late final NewRouteManager originalRouteRouteManager;
  final Set<ZoomToFactor> configSet;
  late final RouteSimplificationConfig config =
      RouteSimplificationConfig(config: configSet);

  final Map<int, NewRouteManager> _zoomToManager = {};

  void _generate() {
    final Map<int, double> zoomToTolerance = {};
    final Map<double, NewRouteManager> toleranceToManager = {};

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
      toleranceToManager[tolerance] = NewRouteManager(
        route: simplifiedRoute,
        sidePoints: [],
        laneWidth: laneWidth,
        laneExtension: laneExtension,
      );
    }

    final Iterable<int> zooms = zoomToTolerance.keys;
    for (final zoom in zooms){
      _zoomToManager[zoom] = toleranceToManager[zoomToTolerance[zoom]]!;
    }
  }

  void _updateRouteManagers({required LatLng currentLocation}) {
    final Iterable<int> keys = _zoomToManager.keys;
    for (final int key in keys) {
      _zoomToManager[key]!.updateStatesOfSidePoints(currentLocation);
    }
    originalRouteRouteManager.updateStatesOfSidePoints(currentLocation);
  }

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

  bool _isPointInLaneByIndex(
    LatLng point,
    Map<int, (List<LatLng>, (double, double))> mapOfLanesData,
    int laneIndex,
  ) {
    final List<LatLng> lane = mapOfLanesData[laneIndex]!.$1;
    return _isPointInLane(point, lane);
  }

  List<LatLng> getRoute3(
      {required LatLngBounds bounds,
      required int zoom,
      LatLng? currentLocation,
      int replaceByOriginalRouteIfLessThan = 200}) {
    final ZoomToFactor currentZoomConfig = config.getConfigForZoom(zoom);
    final List<LatLng> currentZoomRoute = _zoomToManager[zoom]!.route;
    final LatLngBounds expandedBounds =
        expandBounds(bounds, currentZoomConfig.boundsExpansionFactor);

    if (currentZoomRoute.isEmpty) return [];
    
    ////////
    print('[GeoUtils:RouteSimplifier]');
    //final int currentZoomRouteAmountOfSegments = currentZoomRoute.length - 1;
    final int originalRouteAmountOfSegments = _route.length - 1;
    ////////

    print(
        '[GeoUtils:RouteSimplifier] use original route: ${currentZoomConfig.isUseOriginalRouteInVisibleArea}');
    if (currentZoomConfig.isUseOriginalRouteInVisibleArea) {
      print(
          '[GeoUtils:RouteSimplifier] current zoom route is empty: ${currentZoomRoute.isEmpty}');
      print('[GeoUtils:RouteSimplifier] expanded bounds $expandedBounds');
      final List<LatLng> detailedRoute =
          _detailRoute(currentZoomRoute, expandedBounds);
      print('[GeoUtils:RouteSimplifier] detailed route created');
      print(
          '[GeoUtils:RouteSimplifier] detailed route is empty: ${detailedRoute.isEmpty}');
      print('[GeoUtils:RouteSimplifier] current location is $currentLocation');
      if (currentLocation != null) {
        final List<LatLng> cuttedDetailedRoute = [currentLocation];
        _updateRouteManagers(currentLocation: currentLocation);

        int originalRouteNextRoutePointIndex =
            originalRouteRouteManager.nextRoutePointIndex;
        LatLng originalRouteNextRoutePoint =
            originalRouteRouteManager.nextRoutePoint;

        ////////
        final bool isIn = _isPointInLaneByIndex(
            currentLocation,
            originalRouteRouteManager.mapOfLanesData,
            originalRouteNextRoutePointIndex);
        print(
            '[GeoUtils:RouteSimplifier] is in lane $originalRouteNextRoutePointIndex: $isIn');
        if (isIn) {
          originalRouteNextRoutePointIndex =
              originalRouteNextRoutePointIndex < originalRouteAmountOfSegments
                  ? originalRouteNextRoutePointIndex + 1
                  : originalRouteNextRoutePointIndex;
          originalRouteNextRoutePoint =
              _route[originalRouteNextRoutePointIndex];
          /*
          print(
              '[GeoUtils:RouteSimplifier] amount of segments: $originalRouteAmountOfSegments');
          print('[GeoUtils:RouteSimplifier] route length: ${_route.length}');

           */
        }

        /*
        print(
            '[GeoUtils:RouteSimplifier] current segment index: ${originalRouteRouteManager.currentSegmentIndex}');
        print(
            '[GeoUtils:RouteSimplifier] next route point index: $originalRouteNextRoutePointIndex');

         */
        ////////

        if (originalRouteNextRoutePoint == currentLocation) {
          return cuttedDetailedRoute;
        }

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
        } else {
          final int currentZoomNextRoutePointIndex =
              _zoomToManager[zoom]!.nextRoutePointIndex;
          cuttedDetailedRoute
              .addAll(detailedRoute.sublist(currentZoomNextRoutePointIndex));
        }

        return cuttedDetailedRoute;
      }
      print('[GeoUtils:RouteSimplifier] detailed route returned');
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

  List<LatLng> _detailRoute(List<LatLng> zoomRoute, LatLngBounds bounds) {
    print('[GeoUtils:RouteSimplifier] step in detailing function');
    print('[GeoUtils:RouteSimplifier] zoomRoute length: ${zoomRoute.length}');
    final List<LatLng> resultPath = [];
    bool insideBounds = false;
    //содержит пары входа и выхода из области видимости
    // проверяется по четности нечетности количества элементов в списке
    final List<LatLng> listOfReplacements = [];

    print('[GeoUtils:RouteSimplifier] start of getting replacements');
    for (final LatLng point in zoomRoute) {
      if (bounds.contains(point)) {
        if (insideBounds == false) listOfReplacements.add(point);
        insideBounds = true;
      } else {
        if (insideBounds == true) listOfReplacements.add(point);
        insideBounds = false;
      }
    }
    print('[GeoUtils:RouteSimplifier] end of getting replacements');
    print(
        '[GeoUtils:RouteSimplifier] replacements list length before check: ${listOfReplacements.length}');

    //на случай если конец пути покрыт зоной видимости, предыдущий цикл не
    // закроет пару замены пути. но при этом надо сделать проверку на дубликаты
    if (listOfReplacements.length.isOdd) listOfReplacements.add(zoomRoute.last);
    print(
        '[GeoUtils:RouteSimplifier] replacements list length after check: ${listOfReplacements.length}');
    print(
        '[GeoUtils:RouteSimplifier] is replacements list empty: ${listOfReplacements.isEmpty}');

    if (listOfReplacements.isEmpty) return zoomRoute;


    print('[GeoUtils:RouteSimplifier] replacement start');
    for (int i = 0; i < (listOfReplacements.length - 1); i += 2) {
      print('[GeoUtils:RouteSimplifier] iterator i: $i');
      final LatLng startPoint = listOfReplacements[i];
      print('[GeoUtils:RouteSimplifier] start point: $startPoint');
      final LatLng endPoint = listOfReplacements[i + 1];
      print('[GeoUtils:RouteSimplifier] end point: $endPoint');
      final int startPointIndexInOriginalRoute = _route.indexOf(startPoint);
      final int endPointIndexInOriginalRoute = _route.indexOf(endPoint);
      print(
          '[GeoUtils:RouteSimplifier] start point index in original route: $startPointIndexInOriginalRoute');
      print(
          '[GeoUtils:RouteSimplifier] end point index in original route: $endPointIndexInOriginalRoute');

      if (resultPath.isEmpty) {
        resultPath.addAll(_route.sublist(0, startPointIndexInOriginalRoute));
      }

      final List<LatLng> detailedRoutePart = _route.sublist(
          startPointIndexInOriginalRoute, endPointIndexInOriginalRoute);
      print(
          '[GeoUtils:RouteSimplifier] is detailed route part empty: ${detailedRoutePart.isEmpty}');
      print(
          '[GeoUtils:RouteSimplifier] detailed route part length: ${detailedRoutePart.length}');
      resultPath.addAll(detailedRoutePart);

      if (i + 1 < listOfReplacements.length - 1) {
        print('[GeoUtils:RouteSimplifier] intermediate segment start');
        resultPath.addAll(_route.sublist(endPointIndexInOriginalRoute,
            _route.indexOf(listOfReplacements[i + 2])));
        print('[GeoUtils:RouteSimplifier] intermediate segment end');
      }
    }

    print('[GeoUtils:RouteSimplifier] replacement end');
    print(
        '[GeoUtils:RouteSimplifier] is result path empty: ${resultPath.isEmpty}');

    print('[GeoUtils:RouteSimplifier] last check');
    resultPath.add(listOfReplacements.last);
    if (resultPath.last == resultPath[resultPath.length - 2]) {
      resultPath.removeAt(resultPath.length - 1);
    }

    print('[GeoUtils:RouteSimplifier] step out detailing function');
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
}
