
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

21 - 20 - original route
19 and less - tolerance = metersToDegrees((tileSideSize) * 0.01)
*/

class PolylineSimplifier {
  PolylineSimplifier({
    required List<LatLng> route,
    required this.configSet,
    double laneWidth = 10,
    double laneExtension = 5,
    double paintingLaneBuffer = 0,
  }) {
    print('[GeoUtils:RS] creating RS');
    _route = RouteManagerCore.checkRouteForDuplications(route);

    /*
    for (int i = 0; i < (_route.length - 1); i++) {
      lanes[i] = _createLane(
        _route[i],
        _route[i + 1],
        shiftLaneWidth,
        shiftLaneExtension,
      );
    }
     */

    _generate(
      laneWidth + paintingLaneBuffer,
      laneExtension + paintingLaneBuffer,
    );

    originalRouteRouteManager = RouteManagerCore(
      route: _route,
      laneWidth: laneWidth + paintingLaneBuffer,
      laneExtension: laneExtension + paintingLaneBuffer,
    );

    shiftedRouteRouteManager = RouteManagerCore(
      route: _route,
      laneWidth: laneWidth + paintingLaneBuffer,
      laneExtension: laneExtension + paintingLaneBuffer,
    );
  }

  List<LatLng> _route = [];
  late final RouteManagerCore originalRouteRouteManager;
  late final RouteManagerCore shiftedRouteRouteManager;
  final Set<ZoomToFactor> configSet;
  late final RouteSimplificationConfig config =
  RouteSimplificationConfig(config: configSet);
  final Map<double, Map<int, int>> _toleranceToMappedZoomRoutes = {};

  ///{tolerance : {original ind : simplified ind}}
  final Map<double, Map<int, int>> _originalToSimplifiedIndexes = {};

  final Map<int, RouteManagerCore> _zoomToManager = {};
  Map<int, List<LatLng>> lanes = {};

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

    final Map<int, int> reversedMapping = {};
    final Iterable<int> simplifiedIndexes = mapping.keys;
    for (final int simplifiedIndex in simplifiedIndexes) {
      reversedMapping[mapping[simplifiedIndex]!] = simplifiedIndex;
    }
    _originalToSimplifiedIndexes[tolerance] = reversedMapping;
  }

  void _generate(double laneWidth, double laneExtension) {
    final Map<int, double> zoomToTolerance = {};
    final Map<double, RouteManagerCore> toleranceToManager = {};

    for (final zoomToFactor in config.config) {
      zoomToTolerance[zoomToFactor.zoom] =
          zoomToFactor.routeSimplificationFactor;
    }

    print('/// original route ${_route.length}');
    final Set<double> tolerances = zoomToTolerance.values.toSet();
    for (final tolerance in tolerances) {
      final List<LatLng> simplifiedRoute;
      simplifiedRoute = PolylineUtil.simplifyRoutePoints(
        points: _route,
        tolerance: tolerance,
      );
      print(
          '/// simplified route ${simplifiedRoute.length} for tolerance $tolerance');
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
      print('[GeoUtils:RS] RM key: $key');
      _zoomToManager[key]!.updateCurrentLocation(currentLocation);
    }
    print('[GeoUtils:RS] updating original RM');
    originalRouteRouteManager.updateCurrentLocation(currentLocation);
    print(
        '[GeoUtils:RM] is original RMC on route ${originalRouteRouteManager.isOnRoute}');
  }

  List<LatLng> getRoute({
    required LatLngBounds bounds,
    required int zoom,
    LatLng? currentLocation,
  }) {
    print('[GeoUtils:RS] ### have been called');
    final ZoomToFactor zoomConfig = config.getConfigForZoom(zoom);
    final LatLngBounds expandedBounds =
    expandBounds(bounds, zoomConfig.boundsExpansionFactor);
    final double tolerance = zoomConfig.routeSimplificationFactor;
    final RouteManagerCore currentZoomRouteManager = _zoomToManager[zoom]!;
    final bool needReplace = zoomConfig.isUseOriginalRouteInVisibleArea;
    int startingPointIndex = 0;
    List<LatLng> resultRoute = [];

    //cutting stage
    if (currentLocation != null) {
      _updateRouteManagers(currentLocation: currentLocation);

      startingPointIndex = needReplace
          ? currentZoomRouteManager.nextRoutePointIndex - 1
          : currentZoomRouteManager.nextRoutePointIndex;
      if (!needReplace) resultRoute.add(currentLocation);

      resultRoute
          .addAll(currentZoomRouteManager.route.sublist(startingPointIndex));
    } else {
      resultRoute = currentZoomRouteManager.route;
    }

    //detailing stage
    if (needReplace) {
      resultRoute = _detailRoute(
        resultRoute,
        expandedBounds,
        tolerance,
        startingPointIndex,
        currentLocation,
      );
    }
    print('[GeoUtils:RS] ### finished');
    return resultRoute;
  }

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
      } else {
        print('[GeoUtils:RS] removed closing point: $a');
        print('[GeoUtils:RS] removed opening point: $b');
      }
    }
    newList.add(list.last);
    return newList;
  }

  List<LatLng> _detailRoute(
      List<LatLng> route,
      LatLngBounds bounds,
      double tolerance,
      int indexExtension,
      LatLng? currentLocation,
      ) {
    final bool isNull = currentLocation == null;
    final Map<int, int> mapping = _toleranceToMappedZoomRoutes[tolerance]!;
    //print('[GeoUtils:RS] mapping length ${mapping.length}');
    //print('[GeoUtils:RS] original route length ${_route.length}');
    //print('[GeoUtils:RS] cutted route length ${route.length}');
    //print('[GeoUtils:RS] indexExtension $indexExtension');
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
    //print('[GeoUtils:RS] replacementsList $replacementsList');

    for (int i = 0; i < (replacementsList.length - 1); i += 2) {
      final int startIndex = replacementsList[i];
      //print('[GeoUtils:RS] startIndex $startIndex');
      final int endIndex = replacementsList[i + 1];
      //print('[GeoUtils:RS] endIndex $endIndex');
      //print('[GeoUtils:RS] extended startIndex ${startIndex + indexExtension}');
      //print('[GeoUtils:RS] extended endIndex ${endIndex + indexExtension}');
      int originalStartIndex = mapping[startIndex + indexExtension]!;
      //print('[GeoUtils:RS] originalStartIndex $originalStartIndex');
      final int originalEndIndex = mapping[endIndex + indexExtension]!;
      //print('[GeoUtils:RS] originalEndIndex $originalEndIndex');

      if (i == 0 && !isNull) {
        final LatLng shiftedLocation = _currentLocationCutter(
          currentLocation,
          originalStartIndex,
          originalRouteRouteManager.nextRoutePointIndex,
        );
        resultPath.add(shiftedLocation);
        shiftedRouteRouteManager.updateCurrentLocation(shiftedLocation);
        originalStartIndex = originalRouteRouteManager.nextRoutePointIndex;
        //print('[GeoUtils:RS] next point $originalStartIndex');
      }
      resultPath.addAll(_route.sublist(originalStartIndex, originalEndIndex));

      if (i + 2 < replacementsList.length) {
        resultPath.addAll(route.sublist(endIndex, replacementsList[i + 2]));
      }
    }

    resultPath.addAll(route.sublist(replacementsList.last));

    //print('[GeoUtils:RS]');
    return resultPath;
  }

  //TODO попробовать зажать текущее местоположение между несколькими точками (упростит обработку)
  //TODO попробвать обрабатывать сдвинутые точки отдельным менеджером и отрисовывать с него (уберёт хвосты при съездах)
  //TODO породумать способ сглаживания изломов (возможно, поможет второй пункт, если ориентироваться на след точку его, а не обычного менеджера)
  LatLng _currentLocationCutter(
      LatLng currentLocation,
      int start,
      int end,
      ) {
    final LatLng _start = _route[end - 1];
    final LatLng _end = _route[end];
    print('[GeoUtils:RS] currentLocation: $currentLocation');

    final LatLng crossPoint1 = _findCrossPoint(currentLocation, _start, _end);

    late (double, double) shift;
    late (double, double) shift1;

    // current shift
    shift1 = (
    _start.latitude - crossPoint1.latitude,
    _start.longitude - crossPoint1.longitude,
    );

    shift = (shift1.$1, shift1.$2);
    return LatLng(
      currentLocation.latitude + shift.$1,
      currentLocation.longitude + shift.$2,
    );
  }

  LatLng _findCrossPoint(LatLng currentLocation, LatLng start, LatLng end) {
    final (double, double) directionVector = (
    end.latitude - start.latitude,
    end.longitude - start.longitude,
    );

    final double a = directionVector.$2;
    final double b = directionVector.$1;
    final double c = directionVector.$1 * currentLocation.longitude -
        directionVector.$2 * currentLocation.latitude;
    final double _c = directionVector.$2 * start.longitude +
        directionVector.$1 * start.latitude;

    if (a == 0 && b != 0) {
      print('[GeoUtils:RS] way 1');
      return LatLng(_c / b, c / b);
    } else if (a != 0 && b == 0) {
      print('[GeoUtils:RS] way 2');
      return LatLng(-(c / a), _c / a);
    } else if (a != 0 && b != 0) {
      print('[GeoUtils:RS] way 3');
      final double y = (b * c + _c * a) / (b * b + a * a);
      final double x = (b / a) * y - (c / a);

      return LatLng(x, y);
    } else {
      print('[GeoUtils:RS] way 4');
      throw ArgumentError('A and B equal to 0 at the same time');
    }
  }

  List<LatLng> getRouteWithIndex({
    required LatLngBounds bounds,
    required int zoom,
    LatLng? currentLocation,
    int? nextPointIndex,
  }) {
    print('[GeoUtils:RS] ### have been called');
    final ZoomToFactor zoomConfig = config.getConfigForZoom(zoom);
    final LatLngBounds expandedBounds =
    expandBounds(bounds, zoomConfig.boundsExpansionFactor);
    final double tolerance = zoomConfig.routeSimplificationFactor;
    final RouteManagerCore currentZoomRouteManager = _zoomToManager[zoom]!;
    final bool needReplace = zoomConfig.isUseOriginalRouteInVisibleArea;
    int startingPointIndex = 0;
    List<LatLng> resultRoute = [];

    //cutting stage
    if (currentLocation != null && nextPointIndex != null) {
      _updateRouteManagers(currentLocation: currentLocation);

      startingPointIndex = needReplace
          ? _findCurrentIndex(nextPointIndex, tolerance) - 1
          : _findCurrentIndex(nextPointIndex, tolerance);
      if (!needReplace) resultRoute.add(currentLocation);

      resultRoute
          .addAll(currentZoomRouteManager.route.sublist(startingPointIndex));
    } else {
      resultRoute = currentZoomRouteManager.route;
    }

    //detailing stage
    if (needReplace) {
      resultRoute = _detailRouteWithIndex(
        resultRoute,
        expandedBounds,
        tolerance,
        startingPointIndex,
        currentLocation,
        nextPointIndex,
      );
    }
    print('[GeoUtils:RS] ### finished');
    return resultRoute;
  }

  List<LatLng> _detailRouteWithIndex(
      List<LatLng> route,
      LatLngBounds bounds,
      double tolerance,
      int indexExtension,
      LatLng? currentLocation,
      int? nextPointInd,
      ) {
    final bool isNull = currentLocation == null || nextPointInd == null;
    final Map<int, int> mapping = _toleranceToMappedZoomRoutes[tolerance]!;
    //print('[GeoUtils:RS] mapping length ${mapping.length}');
    //print('[GeoUtils:RS] original route length ${_route.length}');
    //print('[GeoUtils:RS] cutted route length ${route.length}');
    //print('[GeoUtils:RS] indexExtension $indexExtension');
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
    //print('[GeoUtils:RS] replacementsList $replacementsList');

    for (int i = 0; i < (replacementsList.length - 1); i += 2) {
      final int startIndex = replacementsList[i];
      //print('[GeoUtils:RS] startIndex $startIndex');
      final int endIndex = replacementsList[i + 1];
      //print('[GeoUtils:RS] endIndex $endIndex');
      //print('[GeoUtils:RS] extended startIndex ${startIndex + indexExtension}');
      //print('[GeoUtils:RS] extended endIndex ${endIndex + indexExtension}');
      int originalStartIndex = mapping[startIndex + indexExtension]!;
      //print('[GeoUtils:RS] originalStartIndex $originalStartIndex');
      final int originalEndIndex = mapping[endIndex + indexExtension]!;
      //print('[GeoUtils:RS] originalEndIndex $originalEndIndex');

      if (i == 0 && !isNull) {
        final LatLng shiftedLocation = _currentLocationCutter(
          currentLocation,
          originalStartIndex,
          originalRouteRouteManager.nextRoutePointIndex,
        );
        resultPath.add(shiftedLocation);
        shiftedRouteRouteManager.updateCurrentLocation(shiftedLocation);
        originalStartIndex = nextPointInd;
        //print('[GeoUtils:RS] next point $originalStartIndex');
      }
      resultPath.addAll(_route.sublist(originalStartIndex, originalEndIndex));

      if (i + 2 < replacementsList.length) {
        resultPath.addAll(route.sublist(endIndex, replacementsList[i + 2]));
      }
    }

    resultPath.addAll(route.sublist(replacementsList.last));

    //print('[GeoUtils:RS]');
    return resultPath;
  }

  int _findCurrentIndex(int currentIndex, double tolerance) {
    final Map<int, int> currentZoomIndexes =
    _originalToSimplifiedIndexes[tolerance]!;
    int supremum = double.maxFinite.toInt();

    final Iterable<int> indexes = currentZoomIndexes.keys;
    for (final int index in indexes) {
      if (index < supremum && currentIndex <= index) supremum = index;
    }
    return currentZoomIndexes[supremum]!;
  }
}