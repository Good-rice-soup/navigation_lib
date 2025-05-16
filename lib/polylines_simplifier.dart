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

      final RouteManagerBasic manager = mConfig.createManager(simplifiedRoute);
      _managersSet.add(manager);
      zooms.forEach((zoom) => _zoomToManager[zoom] = manager);
    }
  }

  List<LatLng> _route = [];
  late final RouteManagerBasic _origRouteRM;
  late final RouteManagerBasic _shiftedRM;
  late final RouteSimplificationConfig _routeConfig;
  final Map<double, Map<int, int>> _simplifiedToOriginalMap = {};
  final Map<double, Map<int, int>> _originalToSimplifiedMap = {};
  final Map<int, RouteManagerBasic> _zoomToManager = {};
  final Set<RouteManagerBasic> _managersSet = {};

  void _updateRouteManagers(LatLng currLoc, [int? curLocInd]) {
    _managersSet.forEach((e) => e.updateCurrentLocation(currLoc, curLocInd));
    _origRouteRM.updateCurrentLocation(currLoc, curLocInd);
  }

  int _cutRoute(
    LatLng currLoc,
    int? currRPInd,
    bool useOriginalRoute,
    double tolerance,
    RouteManagerBasic manager,
    List<LatLng> resultRoute,
  ) {
    int startingPointIndex = 0;
    _updateRouteManagers(currLoc, currRPInd);

    if (currRPInd != null) {
      if (currRPInd >= _route.length || currRPInd < 0) {
        throw ArgumentError('nextPointIndex out of range: $currRPInd');
      }

      final Map<int, int> indexes = _originalToSimplifiedMap[tolerance]!;
      final List<int> sortedInd = indexes.keys.toList()..sort();
      final int ind = indexes[sortedInd.firstWhere((k) => k >= currRPInd + 1)]!;

      startingPointIndex = useOriginalRoute ? ind - 1 : ind;
    } else {
      startingPointIndex = useOriginalRoute
          ? manager.currentRoutePointIndex
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
    int? currRPInd,
  ) {
    final bool locIsNull = currLoc == null;
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
        final int nextRPInd = currRPInd ?? _origRouteRM.nextRoutePointIndex;
        final LatLng shiftedLoc = getPointProjection(
            currLoc, _route[nextRPInd - 1], _route[nextRPInd]);
        resultPath.add(shiftedLoc);
        _shiftedRM.updateCurrentLocation(shiftedLoc, currRPInd);
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
    LatLng? currentLocation,
    int? currentRoutePointIndex,
  ]) {
    final ZoomConfig zoomConfig = _routeConfig.getConfig(zoom);
    final double tolerance = zoomConfig.simplificationTolerance;
    final bool useOriginalRoute = zoomConfig.useOriginalRouteInView;
    final RouteManagerBasic manager = _zoomToManager[zoom]!;
    int startingPointIndex = 0;
    List<LatLng> route = [];

    if (currentLocation != null) {
      startingPointIndex = _cutRoute(currentLocation, currentRoutePointIndex,
          useOriginalRoute, tolerance, manager, route);
    } else {
      route = manager.route;
    }

    if (useOriginalRoute) {
      route = _detailRoute(
        route,
        expandBounds(bounds, zoomConfig.boundsExpansion),
        tolerance,
        startingPointIndex,
        currentLocation,
        currentRoutePointIndex,
      );
    }
    return route;
  }
}
