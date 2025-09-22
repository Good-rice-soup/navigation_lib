import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'config_classes.dart';
import 'geo_utils.dart';
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
*/

class PolylineSimplifier {
  PolylineSimplifier({
    required List<LatLng> route,
    required Set<ZoomConfig> routeConfig,
  }) {
    _routeConfig = RouteSimplificationConfig(routeConfig);

    final List<LatLng> _route = checkForDuplications(route);
    _originalRouteLen = _route.length;

    final Map<double, Set<int>> toleranceGroups = {};
    for (final ZoomConfig config in _routeConfig.zoomConfigs.values) {
      toleranceGroups
          .putIfAbsent(config.simplificationTolerance, () => {})
          .add(config.zoomLevel);
    }

    for (final MapEntry<double, Set<int>> entry in toleranceGroups.entries) {
      final double tolerance = entry.key;
      final Set<int> zooms = entry.value;

      final Map<int, int> smpToOrg = {};
      final List<LatLng> simplifiedRoute =
          rdpRouteSimplifier(_route, tolerance, mapping: smpToOrg);

      final Map<int, int> orgToSmp =
          smpToOrg.map((simpInd, origInd) => MapEntry(origInd, simpInd));

      final List<int> keys = orgToSmp.keys.toList();

      zooms.forEach((zoom) => _zoomToRoute[zoom] =
          (keys: keys, orgToSmp: orgToSmp, route: simplifiedRoute));
    }
    _shiftedCurrLoc = route.first;
  }

  late final int _originalRouteLen;
  final Map<int, ({List<int> keys, Map<int, int> orgToSmp, List<LatLng> route})>
      _zoomToRoute = {};
  late LatLng _shiftedCurrLoc;
  late final RouteSimplificationConfig _routeConfig;
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

  List<List<LatLng>> _boundRoute(
    List<LatLng> route,
    LatLngBounds bounds, [
    LatLng? currLoc,
    bool isOnRoute = false,
  ]) {
    final bool locIsNull = currLoc == null;
    bool insideBounds = false;
    int currentRoutePart = 0;
    final List<List<LatLng>> result = locIsNull
        ? [[]]
        : [
            [route[0], route[1]] // wraps the current location
          ];

    //TODO: remove last if empty and not one
    for (int i = locIsNull ? 0 : 2; i < route.length; i++) {
      final LatLng point = route[i];
      if (bounds.contains(point)) {
        result[currentRoutePart].add(point);
        insideBounds = true;
      } else {
        if (insideBounds) {
          currentRoutePart++;
          result.add([]);
          insideBounds = false;
        }
      }
    }

    //TODO: check is it necessary
    if (result.first.isEmpty) return [[]];

    if (!locIsNull) {
      _shiftedCurrLoc = getPointProjection(currLoc, result[0][0], result[0][1]);
      if (isOnRoute) {
        result[0][0] = _shiftedCurrLoc;
      } else if (getDistance(currLoc, _shiftedCurrLoc) <= outOfRouteDist) {
        result[0][0] = _shiftedCurrLoc;
      }
    }
    return result;
  }

  int infimum(List<int> sortedList, int value) {
    int left = 0;
    int right = sortedList.length - 1;
    int result = -1;

    while (left <= right) {
      final int mid = (left + right) ~/ 2;
      if (sortedList[mid] <= value) {
        result = sortedList[mid];
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }

    return result;
  }

  List<List<LatLng>> getRoute({
    required LatLngBounds bounds,
    required int zoom,
  }) {
    final ZoomConfig zoomConfig = _routeConfig.getConfig(zoom);
    final ({
      List<int> keys,
      Map<int, int> orgToSmp,
      List<LatLng> route
    }) zoomRouteData = _zoomToRoute[zoom]!;

    return _boundRoute(
        zoomRouteData.route, expandBounds(bounds, zoomConfig.boundsExpansion));
  }

  List<List<LatLng>> getRouteFromPoint({
    required LatLngBounds bounds,
    required int zoom,
    required LatLng currLoc,
    required int currRoutePointInd,
    required bool isOnRoute,
  }) {
    final ZoomConfig zoomConfig = _routeConfig.getConfig(zoom);
    final ({
      List<int> keys,
      Map<int, int> orgToSmp,
      List<LatLng> route
    }) zoomRouteData = _zoomToRoute[zoom]!;

    if (currRoutePointInd < 0 || currRoutePointInd >= _originalRouteLen) {
      throw ArgumentError('currRoutePointInd not in possible range of indexes');
    }

    return _boundRoute(
      zoomRouteData.route.sublist(zoomRouteData
          .orgToSmp[infimum(zoomRouteData.keys, currRoutePointInd)]!),
      expandBounds(bounds, zoomConfig.boundsExpansion),
      currLoc,
      isOnRoute,
    );
  }

  LatLng get shiftedCurrentLocation => _shiftedCurrLoc;
}
