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

class _ManagerConfig {
  const _ManagerConfig({
    required this.searchRectWidth,
    required this.searchRectExtension,
    required this.finishLineDist,
    required this.lengthOfLists,
    required this.additionalChecksDist,
    required this.maxVectDeviationInDeg,
  });

  final double searchRectWidth;
  final double searchRectExtension;
  final double finishLineDist;
  final int lengthOfLists;
  final double additionalChecksDist;
  final double maxVectDeviationInDeg;

  RouteManagerCore createManager(List<LatLng> route) {
    return RouteManagerCore(
        route: route,
        searchRectWidth: searchRectWidth,
        searchRectExtension: searchRectExtension,
        finishLineDist: finishLineDist,
        additionalChecksDist: additionalChecksDist,
        maxVectDeviationInDeg: maxVectDeviationInDeg);
  }
}

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
    final _ManagerConfig mConfig = _ManagerConfig(
        searchRectWidth: searchRectWidth,
        searchRectExtension: searchRectExtension,
        finishLineDist: finishLineDist,
        lengthOfLists: lengthOfLists,
        additionalChecksDist: additionalChecksDist,
        maxVectDeviationInDeg: maxVectDeviationInDeg);

    _origRouteRM = mConfig.createManager(route);
    _shiftedRM = mConfig.createManager(route);
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

      final RouteManagerCore manager = mConfig.createManager(simplifiedRoute);
      zooms.forEach((zoom) => _zoomToManager[zoom] = manager);
    }
    _managersSet.addAll(_zoomToManager.values);
  }

  List<LatLng> _route = [];
  late final RouteManagerCore _origRouteRM;
  late final RouteManagerCore _shiftedRM;
  late final RouteSimplificationConfig _routeConfig;
  final Map<double, Map<int, int>> _simplifiedToOriginalMap = {};
  final Map<double, Map<int, int>> _originalToSimplifiedMap = {};
  final Map<int, RouteManagerCore> _zoomToManager = {};
  final Set<RouteManagerCore> _managersSet = {};

  void _updateRouteManagers(LatLng currLoc, [int? curLocInd]) {
    _managersSet.forEach((e) => e.updateCurrentLocation(currLoc, curLocInd));
    _origRouteRM.updateCurrentLocation(currLoc, curLocInd);
  }

  int _cutRoute(
    LatLng currLoc,
    int? nextPointInd,
    bool useOriginalRoute,
    double tolerance,
    RouteManagerCore manager,
    List<LatLng> resultRoute,
  ) {
    int startingPointIndex = 0;
    _updateRouteManagers(
        currLoc, nextPointInd == null ? nextPointInd : nextPointInd - 1);

    if (nextPointInd != null) {
      if (nextPointInd >= _route.length || nextPointInd <= 0) {
        throw ArgumentError('nextPointIndex out of range: $nextPointInd');
      }

      final Map<int, int> indexes = _originalToSimplifiedMap[tolerance]!;
      final List<int> sortedKeys = indexes.keys.toList()..sort();
      final int ind = indexes[sortedKeys.firstWhere((k) => k >= nextPointInd)]!;

      startingPointIndex = useOriginalRoute ? ind - 1 : ind;
    } else {
      startingPointIndex = useOriginalRoute
          ? manager.nextRoutePointIndex - 1
          : manager.nextRoutePointIndex;
    }

    if (!useOriginalRoute) resultRoute.add(currLoc);
    resultRoute.addAll(manager.route.sublist(startingPointIndex));

    return startingPointIndex;
  }

  // elements are arranged in increasing order
  List<int> _segmentConnector(List<int> list) {
    final List<int> newList = [list.first];
    for (int i = 1; i < list.length - 1; i += 2) {
      final int a = list[i], b = list[i + 1];
      if (b - a != 1) newList.addAll([a, b]);
    }
    newList.add(list.last);
    return newList;
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
        final LatLng shiftedLoc = getPointProjection(
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

  List<LatLng> getRoute(
    LatLngBounds bounds,
    int zoom, [
    LatLng? currLoc,
    int? nextPointInd,
  ]) {
    final ZoomConfig zoomConfig = _routeConfig.getConfig(zoom);
    final double tolerance = zoomConfig.simplificationTolerance;
    final bool useOriginalRoute = zoomConfig.useOriginalRouteInView;
    final RouteManagerCore manager = _zoomToManager[zoom]!;
    int startingPointIndex = 0;
    List<LatLng> route = [];

    if (currLoc != null) {
      startingPointIndex = _cutRoute(
          currLoc, nextPointInd, useOriginalRoute, tolerance, manager, route);
    } else {
      route = manager.route;
    }

    if (useOriginalRoute) {
      route = _detailRoute(
        route,
        expandBounds(bounds, zoomConfig.boundsExpansion),
        tolerance,
        startingPointIndex,
        currLoc,
        nextPointInd,
      );
    }
    return route;
  }
}
