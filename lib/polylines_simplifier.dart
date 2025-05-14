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

    //TODO: check do we need it
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

  void _updateRouteManagers({required LatLng currentLocation}) {
    final Iterable<int> keys = _zoomToManager.keys;
    for (final int key in keys) {
      _zoomToManager[key]!.updateCurrentLocation(currentLocation);
    }

    _origRouteRM.updateCurrentLocation(currentLocation);
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

  List<LatLng> getRoute({
    required LatLngBounds bounds,
    required int zoom,
    LatLng? currentLocation,
  }) {
    final ZoomConfig zoomConfig = _routeConfig.getConfig(zoom);
    final LatLngBounds expandedBounds =
        expandBounds(bounds, expFactor: zoomConfig.boundsExpansion);
    final double tolerance = zoomConfig.simplificationTolerance;
    final RouteManagerCore currentZoomRouteManager = _zoomToManager[zoom]!;
    final bool useOriginalRoute = zoomConfig.useOriginalRouteInView;
    int startingPointIndex = 0;
    List<LatLng> resultRoute = [];

    //cutting stage
    if (currentLocation != null) {
      _updateRouteManagers(currentLocation: currentLocation);

      startingPointIndex = useOriginalRoute
          ? currentZoomRouteManager.nextRoutePointIndex - 1
          : currentZoomRouteManager.nextRoutePointIndex;
      if (!useOriginalRoute) resultRoute.add(currentLocation);

      resultRoute
          .addAll(currentZoomRouteManager.route.sublist(startingPointIndex));
    } else {
      resultRoute = currentZoomRouteManager.route;
    }

    //detailing stage
    if (useOriginalRoute) {
      resultRoute = _detailRoute(
        resultRoute,
        expandedBounds,
        tolerance,
        startingPointIndex,
        currentLocation,
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
  ) {
    final bool isNull = currLoc == null;
    final Map<int, int> mapping = _simplifiedToOriginalMap[tolerance]!;

    final List<LatLng> resultPath = [];
    bool insideBounds = false;
    //содержит пары входа и выхода из области видимости function
    // проверяется по четности нечетности количества элементов в списке
    List<int> replacementsList = isNull ? [] : [0, 1];

    final int iteratorStart = isNull ? 0 : 2;
    for (int i = iteratorStart; i < route.length; i++) {
      if (bounds.contains(route[i])) {
        if (insideBounds == false) replacementsList.add(i);
        insideBounds = true;
      } else {
        if (insideBounds == true) replacementsList.add(i);
        insideBounds = false;
      }
    }

    if (replacementsList.isEmpty) {
      return route;
    } else if (replacementsList.length.isOdd) {
      replacementsList.add(route.length - 1);
    } else if (isNull) {
      resultPath.addAll(route.sublist(0, replacementsList.first));
    }
    replacementsList = _segmentConnector(replacementsList);

    for (int i = 0; i < (replacementsList.length - 1); i += 2) {
      final int startInd = replacementsList[i];
      final int endInd = replacementsList[i + 1];
      int origStartInd = mapping[startInd + indexExtension]!;
      final int origEndInd = mapping[endInd + indexExtension]!;

      if (i == 0 && !isNull) {
        final int nextRPInd = _origRouteRM.nextRoutePointIndex;
        final LatLng shiftedLoc = _getPointProjection(
            currLoc, _route[nextRPInd - 1], _route[nextRPInd]);
        resultPath.add(shiftedLoc);
        _shiftedRM.updateCurrentLocation(shiftedLoc);
        origStartInd = _origRouteRM.nextRoutePointIndex;
      }
      resultPath.addAll(_route.sublist(origStartInd, origEndInd));

      if (i + 2 < replacementsList.length) {
        resultPath.addAll(route.sublist(endInd, replacementsList[i + 2]));
      }
    }

    resultPath.addAll(route.sublist(replacementsList.last));
    return resultPath;
  }

  List<LatLng> getRouteWithIndex({
    required LatLngBounds bounds,
    required int zoom,
    LatLng? currentLocation,
    int? nextPointIndex,
  }) {
    final ZoomConfig zoomConfig = _routeConfig.getConfig(zoom);
    final LatLngBounds expandedBounds =
        expandBounds(bounds, expFactor: zoomConfig.boundsExpansion);
    final double tolerance = zoomConfig.simplificationTolerance;
    final RouteManagerCore currentZoomRouteManager = _zoomToManager[zoom]!;
    final bool useOriginalRoute = zoomConfig.useOriginalRouteInView;
    int startingPointIndex = 0;
    List<LatLng> resultRoute = [];

    //cutting stage
    if (currentLocation != null && nextPointIndex != null) {
      _updateRouteManagers(currentLocation: currentLocation);

      final Map<int, int> indexes = _originalToSimplifiedMap[tolerance]!;
      final List<int> sortedKeys = indexes.keys.toList()..sort();
      final int index = indexes[sortedKeys.firstWhere(
        (k) => k >= nextPointIndex,
        orElse: () => throw Exception('No key ≥ $nextPointIndex'),
      )]!;

      startingPointIndex = useOriginalRoute ? index - 1 : index;
      if (!useOriginalRoute) resultRoute.add(currentLocation);

      resultRoute
          .addAll(currentZoomRouteManager.route.sublist(startingPointIndex));
    } else {
      resultRoute = currentZoomRouteManager.route;
    }

    //detailing stage
    if (useOriginalRoute) {
      resultRoute = _detailRouteWithIndex(
        resultRoute,
        expandedBounds,
        tolerance,
        startingPointIndex,
        currentLocation,
        nextPointIndex,
      );
    }

    return resultRoute;
  }

  List<LatLng> _detailRouteWithIndex(
    List<LatLng> route,
    LatLngBounds bounds,
    double tolerance,
    int indexExtension,
    LatLng? currLoc,
    int? nextPointInd,
  ) {
    final bool isNull = currLoc == null || nextPointInd == null;
    final Map<int, int> mapping = _simplifiedToOriginalMap[tolerance]!;

    final List<LatLng> resultPath = [];
    bool insideBounds = false;
    //содержит пары входа и выхода из области видимости function
    // проверяется по четности нечетности количества элементов в списке
    List<int> replacementsList = isNull ? [] : [0, 1];

    final int iteratorStart = isNull ? 0 : 2;
    for (int i = iteratorStart; i < route.length; i++) {
      if (bounds.contains(route[i])) {
        if (insideBounds == false) replacementsList.add(i);
        insideBounds = true;
      } else {
        if (insideBounds == true) replacementsList.add(i);
        insideBounds = false;
      }
    }

    if (replacementsList.isEmpty) {
      return route;
    } else if (replacementsList.length.isOdd) {
      replacementsList.add(route.length - 1);
    } else if (isNull) {
      resultPath.addAll(route.sublist(0, replacementsList.first));
    }
    replacementsList = _segmentConnector(replacementsList);

    for (int i = 0; i < (replacementsList.length - 1); i += 2) {
      final int startInd = replacementsList[i];
      final int endInd = replacementsList[i + 1];

      int origStartInd = mapping[startInd + indexExtension]!;
      final int origEndInd = mapping[endInd + indexExtension]!;

      if (i == 0 && !isNull) {
        final int nextRPInd = _origRouteRM.nextRoutePointIndex;
        final LatLng shiftedLoc = _getPointProjection(
            currLoc, _route[nextRPInd - 1], _route[nextRPInd]);
        resultPath.add(shiftedLoc);
        _shiftedRM.updateCurrentLocation(shiftedLoc);
        origStartInd = nextPointInd;
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