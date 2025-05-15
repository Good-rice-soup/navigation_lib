import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'config_classes.dart';
import 'geo_utils.dart';
import 'polyline_util.dart';
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
*/

class PolylineSimplifier {
  PolylineSimplifier({
    required List<LatLng> route,
    required Set<ZoomConfig> routeConfig,
    double searchRectWidth = 10,
    double searchRectExtension = 5,
    double finishLineDist = 5,
    int lengthOfLists = 2,
    double additionalChecksDist = 100,
    double maxVectDeviationInDeg = 45,
  }) {
    _routeConfig = RouteSimplificationConfig(routeConfig);

    _origRouteRM = RouteManagerCore(
        route: route,
        searchRectWidth: searchRectWidth,
        searchRectExtension: searchRectExtension,
        finishLineDist: finishLineDist,
        lengthOfLists: lengthOfLists,
        additionalChecksDist: additionalChecksDist,
        maxVectDeviationInDeg: maxVectDeviationInDeg);

    _route = _origRouteRM.route;

    _shiftedRM = RouteManagerCore(
        route: route,
        searchRectWidth: searchRectWidth,
        searchRectExtension: searchRectExtension,
        finishLineDist: finishLineDist,
        lengthOfLists: lengthOfLists,
        additionalChecksDist: additionalChecksDist,
        maxVectDeviationInDeg: maxVectDeviationInDeg);

    final Map<double, Set<int>> toleranceGroups = {};
    for (final ZoomConfig config in _routeConfig.zoomConfigs.values) {
      toleranceGroups
          .putIfAbsent(config.simplificationTolerance, () => {})
          .add(config.zoomLevel);
    }

    for (final MapEntry<double, Set<int>> entry in toleranceGroups.entries) {
      final tolerance = entry.key;
      final zooms = entry.value;

      final Map<int, int> simplifiedToOriginal = {};
      final List<LatLng> simplifiedRoute =
          rdpRouteSimplifier(_route, tolerance, mapping: simplifiedToOriginal);

      _simplifiedToOriginalMap[tolerance] = simplifiedToOriginal;
      _originalToSimplifiedMap[tolerance] = simplifiedToOriginal
          .map((simpInd, origInd) => MapEntry(origInd, simpInd));

      final RouteManagerCore manager = RouteManagerCore(
          route: simplifiedRoute,
          searchRectWidth: searchRectWidth,
          searchRectExtension: searchRectExtension,
          finishLineDist: finishLineDist,
          lengthOfLists: lengthOfLists,
          additionalChecksDist: additionalChecksDist,
          maxVectDeviationInDeg: maxVectDeviationInDeg);

      for (final int zoom in zooms) {
        _zoomToManager[zoom] = manager;
      }
    }
  }

  List<LatLng> _route = [];
  late final RouteManagerCore _origRouteRM;
  late final RouteManagerCore _shiftedRM;
  late final RouteSimplificationConfig _routeConfig;
  final Map<double, Map<int, int>> _simplifiedToOriginalMap = {};
  final Map<double, Map<int, int>> _originalToSimplifiedMap = {};
  final Map<int, RouteManagerCore> _zoomToManager = {};

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
      }
    }
    newList.add(list.last);
    return newList;
  }

  void _updateRouteManagers(LatLng currLoc, [int? curLocInd]) {
    final Iterable<int> keys = _zoomToManager.keys;
    for (final int key in keys) {
      _zoomToManager[key]!.updateCurrentLocation(currLoc, curLocInd);
    }

    _origRouteRM.updateCurrentLocation(currLoc, curLocInd);
  }

  LatLng _getPointProjection(LatLng currLoc, LatLng start, LatLng end) {
    final double dLat = end.latitude - start.latitude;
    final double dLng = end.longitude - start.longitude;

    if (dLat == 0 && dLng == 0) throw ArgumentError('Start and end are same');

    // start(x1, y1), end(x2, y2), point(x0, y0)
    final double x0 = currLoc.latitude;
    final double x1 = start.latitude;
    final double y0 = currLoc.longitude;
    final double y1 = start.longitude;

    if (dLng == 0 && dLat != 0) return LatLng(x0, y1);
    if (dLng != 0 && dLat == 0) return LatLng(x1, y0);

    // coefficients in line equations system Ax + By + C = 0
    // A = y2 - y1, B = x2 - x1
    final double aa = dLng * dLng; // A^2
    final double bb = dLat * dLat; // B^2
    final double ab = dLng * dLat;
    final double denominator = aa + bb;

    final double y = (bb * y1 + ab * (x0 - x1) + aa * y0) / denominator;
    final double x = (bb * y1 + ab * (x0 - x1) + aa * y0) / denominator;

    return LatLng(x, y);
  }

  List<LatLng> getRoute(
    LatLngBounds bounds,
    int zoom, [
    LatLng? currLoc,
    int? nextPointInd,
  ]) {
    final ZoomConfig zoomConfig = _routeConfig.getConfig(zoom);
    final LatLngBounds expandedBounds =
        expandBounds(bounds, zoomConfig.boundsExpansion);
    final double tolerance = zoomConfig.simplificationTolerance;
    final RouteManagerCore manager = _zoomToManager[zoom]!;
    final bool useOriginalRoute = zoomConfig.useOriginalRouteInView;
    int startingPointIndex = 0;
    List<LatLng> resultRoute = [];

    if (currLoc != null) {
      final bool indIsNull = nextPointInd == null;
      _updateRouteManagers(
          currLoc, indIsNull ? nextPointInd : nextPointInd - 1);

      if (nextPointInd != null) {
        if (nextPointInd >= _route.length || nextPointInd <= 0) {
          throw ArgumentError('nextPointIndex out of range: $nextPointInd');
        }

        final Map<int, int> indexes = _originalToSimplifiedMap[tolerance]!;
        final List<int> sortedKeys = indexes.keys.toList()..sort();
        final int index =
            indexes[sortedKeys.firstWhere((k) => k >= nextPointInd)]!;

        startingPointIndex = useOriginalRoute ? index - 1 : index;
      } else {
        startingPointIndex = useOriginalRoute
            ? manager.nextRoutePointIndex - 1
            : manager.nextRoutePointIndex;
      }

      if (!useOriginalRoute) resultRoute.add(currLoc);
      resultRoute.addAll(manager.route.sublist(startingPointIndex));
    } else {
      resultRoute = manager.route;
    }

    if (useOriginalRoute) {
      resultRoute = _detailRoute(
        resultRoute,
        expandedBounds,
        tolerance,
        startingPointIndex,
        currLoc,
        nextPointInd,
      );
    }

    return resultRoute;
  }

  List<LatLng> _detailRoute(
    List<LatLng> route,
    LatLngBounds bounds,
    double tolerance,
    int indexExtension,
    LatLng? currLoc,
    int? nextPointInd,
  ) {
    final bool locIsNull = currLoc == null;
    final bool indIsNull = nextPointInd == null;
    final Map<int, int> mapping = _simplifiedToOriginalMap[tolerance]!;
    final List<LatLng> resultPath = [];
    bool insideBounds = false;
    List<int> replacementsList = locIsNull ? [] : [0, 1];

    for (int i = locIsNull ? 0 : 2; i < route.length; i++) {
      if (bounds.contains(route[i])) {
        if (!insideBounds) replacementsList.add(i);
        insideBounds = true;
      } else {
        if (insideBounds) replacementsList.add(i);
        insideBounds = false;
      }
    }

    if (replacementsList.isEmpty) return route;
    if (replacementsList.length.isOdd) replacementsList.add(route.length - 1);
    if (locIsNull) resultPath.addAll(route.sublist(0, replacementsList.first));
    replacementsList = _segmentConnector(replacementsList);

    for (int i = 0; i < replacementsList.length - 1; i += 2) {
      final int startInd = replacementsList[i];
      final int endInd = replacementsList[i + 1];
      int origStartInd = mapping[startInd + indexExtension]!;
      final int origEndInd = mapping[endInd + indexExtension]!;

      if (i == 0 && !locIsNull) {
        final int nextRPInd = nextPointInd ?? _origRouteRM.nextRoutePointIndex;
        final LatLng shiftedLoc = _getPointProjection(
            currLoc, _route[nextRPInd - 1], _route[nextRPInd]);
        resultPath.add(shiftedLoc);
        _shiftedRM.updateCurrentLocation(
            shiftedLoc, indIsNull ? nextPointInd : nextPointInd - 1);
        origStartInd = _shiftedRM.nextRoutePointIndex;
      }

      resultPath.addAll(_route.sublist(origStartInd, origEndInd));
      if (i + 2 < replacementsList.length) {
        resultPath.addAll(route.sublist(endInd, replacementsList[i + 2]));
      }
    }

    resultPath.addAll(route.sublist(replacementsList.last));
    return resultPath;
  }
}
