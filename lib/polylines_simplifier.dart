import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'config_classes.dart';
import 'copy_policy.dart';
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

    final CopyPolicy policy = CopyPolicy(
      deepCopyRoute: false,
      deepCopySearchRects: false,
      deepCopySidePoints: false,
    );

    _origRouteRM = RouteManagerBasic(
      route: route,
      searchRectWidth: searchRectWidth,
      searchRectExtension: searchRectExtension,
      additionalChecksDist: additionalChecksDist,
      maxVectDeviationInDeg: maxVectDeviationInDeg,
      sameCordConst: sameCordConst,
      finishLineDist: finishLineDist,
      lengthOfLists: lengthOfLists,
      policy: policy,
    );

    final List<LatLng> _route = _origRouteRM.route;

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

  late final RouteManagerBasic _origRouteRM;
  final Map<int, ({List<int> keys, Map<int, int> orgToSmp, List<LatLng> route})>
      _zoomToRoute = {};
  late LatLng _shiftedCurrLoc;
  late final RouteSimplificationConfig _routeConfig;
  double outOfRouteDist = 10;

  List<List<LatLng>> _boundRoute(
    List<LatLng> route,
    LatLngBounds bounds,
    LatLng? currLoc,
  ) {
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
      if (_origRouteRM.isOnRoute) {
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

  List<List<LatLng>> getRoute(
    LatLngBounds bounds,
    int zoom, [
    LatLng? currLoc,
    int? currRoutePointInd,
  ]) {
    final ZoomConfig zoomConfig = _routeConfig.getConfig(zoom);
    final ({
      List<int> keys,
      Map<int, int> orgToSmp,
      List<LatLng> route
    }) zoomRouteData = _zoomToRoute[zoom]!;

    if (currLoc != null) {
      _origRouteRM.updateCurrentLocation(currLoc, currRoutePointInd);

      return _boundRoute(
        zoomRouteData.route.sublist(zoomRouteData.orgToSmp[
            infimum(zoomRouteData.keys, _origRouteRM.currentRoutePointIndex)]!),
        expandBounds(bounds, zoomConfig.boundsExpansion),
        currLoc,
      );
    } else {
      return _boundRoute(
        zoomRouteData.route,
        expandBounds(bounds, zoomConfig.boundsExpansion),
        currLoc,
      );
    }
  }

  LatLng get shiftedCurrentLocation => _shiftedCurrLoc;
}
