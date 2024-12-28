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
    final Iterable<int> keys = _zoomToManager.keys;
    for (final int key in keys) {
      _zoomToManager[key]!.updateCurrentLocation(currentLocation);
    }
    originalRouteRouteManager.updateCurrentLocation(currentLocation);
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
  }) {
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
        print('[GeoUtils:RouteSimplifier] removed closing point: $a');
        print('[GeoUtils:RouteSimplifier] removed opening point: $b');
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
    final List<LatLng> resultPath = [];
    bool insideBounds = false;
    //содержит пары входа и выхода из области видимости function
    // проверяется по четности нечетности количества элементов в списке
    List<int> replacementsList = isNull ? [] : [0, 1];

    int i = isNull ? 0 : 2;
    for (final LatLng point in route) {
      if (bounds.contains(point)) {
        if (insideBounds == false) replacementsList.add(i);
        insideBounds = true;
      } else {
        if (insideBounds == true) replacementsList.add(i);
        insideBounds = false;
      }
      i++;
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
      final int startIndex = replacementsList[i];
      final int endIndex = replacementsList[i + 1];
      int originalStartIndex = mapping[startIndex + indexExtension]!;
      final int originalEndIndex = mapping[endIndex + indexExtension]!;

      if (i == 0 && !isNull) {
        final LatLng shiftedLocation = _currentLocationCutter(
          currentLocation,
          originalStartIndex,
          originalRouteRouteManager.nextRoutePointIndex,
        );
        resultPath.add(shiftedLocation);
        originalStartIndex = originalRouteRouteManager.nextRoutePointIndex;
      }
      resultPath.addAll(_route.sublist(originalStartIndex, originalEndIndex));

      if (i + 2 < replacementsList.length) {
        resultPath.addAll(route.sublist(endIndex, replacementsList[i + 2]));
      }
    }

    resultPath.addAll(route.sublist(replacementsList.last));

    return resultPath;
  }

  LatLng _currentLocationCutter(
    LatLng currentLocation,
    int start,
    int end,
  ) {
    for (int i = end; i >= start + 1; i--) {
      final LatLng _start = _route[i - 1];
      final LatLng _end = _route[i];
      final LatLng crossPoint = _findCrossPoint(currentLocation, _start, _end);

      final (double, double) shift = (
        _start.latitude - crossPoint.latitude,
        _start.longitude - crossPoint.longitude,
      );

      final LatLng shiftedLocation = LatLng(
        currentLocation.latitude + shift.$1,
        currentLocation.longitude + shift.$2,
      );

      final LatLngBounds bounds =
          LatLngBounds(southwest: _start, northeast: _end);
      if (bounds.contains(shiftedLocation)) return shiftedLocation;
    }
    print('There is no shifted point');
    return currentLocation;
  }

  LatLng _findCrossPoint(LatLng currentLocation, LatLng start, LatLng end) {
    final (double, double) directionVector = (
      end.latitude - start.latitude,
      end.longitude - start.longitude,
    );

    // A, B, C coefficients in linear equation
    final (double, double, double) lineEquation = (
      directionVector.$2,
      -directionVector.$1,
      directionVector.$1 * currentLocation.longitude -
          directionVector.$2 * currentLocation.latitude
    );

    // A`, B`, C` coefficients in linear equation
    final (double, double, double) perpendicularLineEquation = (
      directionVector.$1,
      directionVector.$2,
      -directionVector.$1 * start.latitude -
          directionVector.$2 * start.longitude
    );

    if (lineEquation.$1 == 0 && lineEquation.$2 != 0) {
      // A == 0, B != 0
      return LatLng(
        -(perpendicularLineEquation.$3 / lineEquation.$2),
        -(lineEquation.$3 / lineEquation.$2),
      );
    } else if (lineEquation.$2 == 0 && lineEquation.$1 != 0) {
      // A != 0, B == 0
      return LatLng(
        -(perpendicularLineEquation.$3 / lineEquation.$1),
        -(lineEquation.$3 / lineEquation.$1),
      );
    } else if (lineEquation.$1 != 0 && lineEquation.$2 != 0) {
      // A != 0, B != 0
      final double a = lineEquation.$1;
      final double b = lineEquation.$2;
      final double c = lineEquation.$3;
      final double _c = perpendicularLineEquation.$3;

      final double y =
          ((_c * a - b * c) * (a * a) - (b * c - a * _c) * (b * b)) /
              (a * a * b * b);
      final double x = -(b / a) * y - (c / a);

      return LatLng(x, y);
    } else {
      throw ArgumentError('A and B equal to 0 at the same time');
    }
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
}
