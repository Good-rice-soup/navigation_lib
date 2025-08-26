import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'config_classes.dart';
import 'geo_utils.dart';
import 'polyline_util.dart';
import 'route_manager_basic.dart';

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
*/

class _ManagerConfig {
  const _ManagerConfig({
    required this.searchRectWidth,
    required this.searchRectExtension,
    required this.additionalChecksDist,
    required this.maxVectDeviationInDeg,
    required this.sameCordConst,
    required this.finishLineDist,
    required this.lengthOfLists,
  });

  final double searchRectWidth;
  final double searchRectExtension;
  final double additionalChecksDist;
  final double maxVectDeviationInDeg;
  final double sameCordConst;
  final double finishLineDist;
  final int lengthOfLists;

  RouteManagerBasic createManager(List<LatLng> route) {
    return RouteManagerBasic(
      route: route,
      searchRectWidth: searchRectWidth,
      searchRectExtension: searchRectExtension,
      additionalChecksDist: additionalChecksDist,
      maxVectDeviationInDeg: maxVectDeviationInDeg,
      sameCordConst: sameCordConst,
      finishLineDist: finishLineDist,
      lengthOfLists: lengthOfLists,
    );
  }
}

class PolylineSimplifier {
  PolylineSimplifier({
    required List<LatLng> route,
    required Set<ZoomConfig> routeConfig,
    double searchRectWidth = 10,
    double searchRectExtension = 5,
    double additionalChecksDist = 100,
    double maxVectDeviationInDeg = 45,
    double sameCordConst = 0.00001,
    double finishLineDist = 5,
    int lengthOfLists = 2,
  }) {
    _routeConfig = RouteSimplificationConfig(routeConfig);
    final _ManagerConfig mConfig = _ManagerConfig(
      searchRectWidth: searchRectWidth,
      searchRectExtension: searchRectExtension,
      additionalChecksDist: additionalChecksDist,
      maxVectDeviationInDeg: maxVectDeviationInDeg,
      sameCordConst: sameCordConst,
      finishLineDist: finishLineDist,
      lengthOfLists: lengthOfLists,
    );

    List<LatLng> _route;
    _origRouteRM = mConfig.createManager(route);
    _route = _origRouteRM.route;

    final Map<double, Set<int>> toleranceGroups = {};
    for (final ZoomConfig config in _routeConfig.zoomConfigs.values) {
      toleranceGroups
          .putIfAbsent(config.simplificationTolerance, () => {})
          .add(config.zoomLevel);
    }

    for (final MapEntry<double, Set<int>> entry in toleranceGroups.entries) {
      final double tolerance = entry.key;
      final Set<int> zooms = entry.value;

      final Map<int, int> simplifiedToOriginal = {};
      final List<LatLng> simplifiedRoute =
          rdpRouteSimplifier(_route, tolerance, mapping: simplifiedToOriginal);

      _simplifiedToOriginalMap[tolerance] = simplifiedToOriginal;
      _originalToSimplifiedMap[tolerance] = simplifiedToOriginal
          .map((simpInd, origInd) => MapEntry(origInd, simpInd));

      final RouteManagerBasic manager = mConfig.createManager(simplifiedRoute);
      _managersSet.add(manager);
      zooms.forEach((zoom) => _zoomToManager[zoom] = manager);
    }
    _shiftedCurrLoc = route.first;
  }

  late final RouteManagerBasic _origRouteRM; //TODO: may be remove
  late LatLng _shiftedCurrLoc;
  late final RouteSimplificationConfig _routeConfig;
  final Map<double, Map<int, int>> _simplifiedToOriginalMap =
      {}; //TODO: should be removed
  final Map<double, Map<int, int>> _originalToSimplifiedMap =
      {}; //TODO: may be remove
  final Map<int, RouteManagerBasic> _zoomToManager = {}; //TODO: may be remove
  final Set<RouteManagerBasic> _managersSet = {}; //TODO: may be remove
  double outOfRouteDist = 10;

  /// Checks the path for duplicate coordinates, and returns the path without duplicates.
  static List<LatLng> checkForDuplications(List<LatLng> route) {
    final List<LatLng> newRoute = [];
    if (route.isNotEmpty) {
      newRoute.add(route[0]);
      for (int i = 1; i < route.length; i++) {
        if (route[i] != route[i - 1]) {
          newRoute.add(route[i]);
        }
      }
    }
    return newRoute;
  }

  void _updateRouteManagers(LatLng currLoc, [int? curLocInd]) {
    if (curLocInd != null) {
      _routeConfig.zoomConfigs.keys.forEach((e) => _zoomToManager[e]!
          .updateCurrentLocation(
              currLoc,
              _originalToSimplifiedMap[_routeConfig
                  .zoomConfigs[e]!.simplificationTolerance]![curLocInd]));
    } else {
      _managersSet.forEach((e) => e.updateCurrentLocation(currLoc));
    }

    _origRouteRM.updateCurrentLocation(currLoc, curLocInd);
  }

  List<List<LatLng>> _boundRoute(
    List<LatLng> route,
    LatLngBounds bounds,
    LatLng? currLoc,
    int? currRPInd,
  ) {
    final bool locIsNull = currLoc == null;
    bool insideBounds = false;
    int currentRoutePart = 0;
    final List<List<LatLng>> rRoute = locIsNull
        ? [[]]
        : [
            [route[0], route[1]] // wraps the current location
          ];

    //TODO: remove last if empty and not one
    for (int i = locIsNull ? 0 : 2; i < route.length; i++) {
      final LatLng point = route[i];
      if (bounds.contains(point)) {
        rRoute[currentRoutePart].add(point);
        insideBounds = true;
      } else {
        if (insideBounds) {
          currentRoutePart++;
          rRoute.add([]);
          insideBounds = false;
        }
      }
    }

    //TODO: check is it necessary
    if (rRoute.first.isEmpty) return [[]];

    if (!locIsNull) {
      final bool shouldAdd; // should we add a current position to the route

      if (_origRouteRM.isOnRoute) {
        shouldAdd = true;
      } else {
        final double dist1 = getDistance(currLoc, rRoute[0][0]);
        final double dist2 = getDistance(currLoc, rRoute[0][1]);
        shouldAdd = dist1 <= outOfRouteDist || dist2 <= outOfRouteDist;
      }

      if (shouldAdd) {
        _shiftedCurrLoc =
            getPointProjection(currLoc, rRoute[0][0], rRoute[0][1]);
        rRoute[0][0] = _shiftedCurrLoc;
      }
    }
    return rRoute;
  }

  List<List<LatLng>> getRoute(
    LatLngBounds bounds,
    int zoom, [
    LatLng? currentLocation,
    int? currentRoutePointIndex,
  ]) {
    final ZoomConfig zoomConfig = _routeConfig.getConfig(zoom);
    final RouteManagerBasic manager = _zoomToManager[zoom]!;

    if (currentLocation != null) {
      _updateRouteManagers(currentLocation, currentRoutePointIndex);

      return _boundRoute(
        [...manager.route.sublist(manager.currentRoutePointIndex)],
        expandBounds(bounds, zoomConfig.boundsExpansion),
        currentLocation,
        currentRoutePointIndex,
      );
    } else {
      return _boundRoute(
        manager.route,
        expandBounds(bounds, zoomConfig.boundsExpansion),
        currentLocation,
        currentRoutePointIndex,
      );
    }
  }

  LatLng get shiftedCurrentLocation => _shiftedCurrLoc;
}
