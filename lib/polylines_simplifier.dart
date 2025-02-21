import 'dart:math';

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
    double laneWidth = 10,
    double laneExtension = 5,
    double paintingLaneBuffer = 0,
    double shiftLaneWidth = 1,
    double shiftLaneExtension = 1,
  }) {
    print('[GeoUtils:RS] creating RS');
    _route = RouteManagerCore.checkRouteForDuplications(route);

    for (int i = 0; i < (_route.length - 1); i++) {
      lanes[i] = _createLane(
        _route[i],
        _route[i + 1],
        shiftLaneWidth,
        shiftLaneExtension,
      );
    }

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

  static const double metersPerDegree = 111195.0797343687;

  List<LatLng> _route = [];
  late final RouteManagerCore originalRouteRouteManager;
  late final RouteManagerCore shiftedRouteRouteManager;
  final Set<ZoomToFactor> configSet;
  late final RouteSimplificationConfig config =
      RouteSimplificationConfig(config: configSet);
  final Map<double, Map<int, int>> _toleranceToMappedZoomRoutes = {};

  final Map<int, RouteManagerCore> _zoomToManager = {};
  Map<int, List<LatLng>> lanes = {};

  List<LatLng> _createLane(
    LatLng start,
    LatLng end,
    double width,
    double extension,
  ) {
    final double deltaLng = end.longitude - start.longitude;
    final double deltaLat = end.latitude - start.latitude;
    final double length = sqrt(deltaLng * deltaLng + deltaLat * deltaLat);

    // Converting lane width to degrees
    final double lngNormal =
        -(deltaLat / length) * _metersToLongitudeDegrees(width, start.latitude);
    final double latNormal =
        (deltaLng / length) * _metersToLatitudeDegrees(width);

    // Converting lane extension to degrees
    final LatLng extendedStart = LatLng(
        start.latitude -
            (deltaLat / length) * _metersToLatitudeDegrees(extension),
        start.longitude -
            (deltaLng / length) *
                _metersToLongitudeDegrees(extension, start.latitude));
    final LatLng extendedEnd = LatLng(
        end.latitude +
            (deltaLat / length) * _metersToLatitudeDegrees(extension),
        end.longitude +
            (deltaLng / length) *
                _metersToLongitudeDegrees(extension, end.latitude));

    return [
      LatLng(
          extendedEnd.latitude + latNormal, extendedEnd.longitude + lngNormal),
      LatLng(
          extendedEnd.latitude - latNormal, extendedEnd.longitude - lngNormal),
      LatLng(extendedStart.latitude - latNormal,
          extendedStart.longitude - lngNormal),
      LatLng(extendedStart.latitude + latNormal,
          extendedStart.longitude + lngNormal),
    ];
  }

  /// Convert meters to latitude degrees.
  double _metersToLatitudeDegrees(double meters) {
    return meters / metersPerDegree;
  }

  /// Convert meters to longitude degrees using latitude.
  double _metersToLongitudeDegrees(double meters, double latitude) {
    return meters / (metersPerDegree * cos(_toRadians(latitude)));
  }

  double _toRadians(double deg) {
    return deg * (pi / 180);
  }

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

  void _generate(double laneWidth, double laneExtension) {
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
      print('[GeoUtils:RS] RM key: $key');
      _zoomToManager[key]!.updateCurrentLocation(currentLocation);
    }
    print('[GeoUtils:RS] updating original RM');
    originalRouteRouteManager.updateCurrentLocation(currentLocation);
    print('[GeoUtils:RM] is original RMC on route ${originalRouteRouteManager.isOnRoute}');
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
    late LatLng shiftedLocation;
    //print('[GeoUtils:RS] start: $start');
    //print('[GeoUtils:RS] end: $end');

    LatLng _start = _route[end - 1];
    LatLng _end = _route[end];
    print('[GeoUtils:RS] currentLocation: $currentLocation');
    //print('[GeoUtils:RS] _start1: $_start');
    //print('[GeoUtils:RS] _end1: $_end');

    final LatLng crossPoint1 = _findCrossPoint(currentLocation, _start, _end);
    //print('[GeoUtils:RS] crossPoint: $crossPoint1');

    late (double, double) shift;
    late (double, double) shift1;
    late (double, double) shift2;
    late (double, double) shift3;

    // current shift
    shift1 = (
      _start.latitude - crossPoint1.latitude,
      _start.longitude - crossPoint1.longitude,
    );

    /*
    if (end - 2 >= 0) {
      _end = _route[end - 1];
      _start = _route[end - 2];
      //print('[GeoUtils:RS] _start2: $_start');
      //print('[GeoUtils:RS] _end2: $_end');

      final LatLng crossPoint2 = _findCrossPoint(currentLocation, _start, _end);
      //print('[GeoUtils:RS] crossPoint2: $crossPoint2');

      // previous shift
      shift2 = (
        _start.latitude - crossPoint2.latitude,
        _start.longitude - crossPoint2.longitude,
      );
    } else {
      shift2 = shift1;
    }

    if (end + 1 <= _route.length - 1) {
      _end = _route[end + 1];
      _start = _route[end];
      //print('[GeoUtils:RS] _start3: $_start');
      //print('[GeoUtils:RS] _end3: $_end');

      final LatLng crossPoint3 = _findCrossPoint(currentLocation, _start, _end);
      //print('[GeoUtils:RS] crossPoint3: $crossPoint3');

      // previous shift
      shift3 = (
        _start.latitude - crossPoint3.latitude,
        _start.longitude - crossPoint3.longitude,
      );
    } else {
      shift3 = shift1;
    }
     */

    /*
    shift = (
      0.5 * shift1.$1 + 0.25 * shift2.$1 + 0.25 * shift3.$1,
      0.5 * shift1.$2 + 0.25 * shift2.$2 + 0.25 * shift3.$2,
    );

     */

    shift = (shift1.$1, shift1.$2);
    //print('[GeoUtils:RS] shift: $shift');

    shiftedLocation = LatLng(
      currentLocation.latitude + shift.$1,
      currentLocation.longitude + shift.$2,
    );
    //print('[GeoUtils:RS] shiftedLocation: $shiftedLocation');

    /*
    LatLngBounds bounds = _start.latitude <= _end.latitude
        ? LatLngBounds(southwest: _start, northeast: _end)
        : LatLngBounds(southwest: _end, northeast: _start);
    bounds = expandBounds(bounds, 1.5);

    if (bounds.contains(shiftedLocation)) return shiftedLocation;
    */

    /*
      final List<LatLng> lane =
          end < _route.length - 1 ? lanes[end]! : lanes[end - 1]!;
      final bool isIn = _isPointInLane(shiftedLocation, lane);
      if (isIn) return shiftedLocation;

     */

    return shiftedLocation;
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

/*
[GeoUtils:RM]: Your route has a duplication of LatLng(45.511791, -122.675633) (№1).
[GeoUtils:RM]: Total amount of duplication 1 duplication
[GeoUtils:RM]:
[GeoUtils:RMC] Your route has a duplication of LatLng(45.511791, -122.675633) (№1).
[GeoUtils:RMC] Total amount of duplication 1 duplication
[GeoUtils:RMC]
[GeoUtils:RMC] Total amount of duplication 0 duplication
[GeoUtils:RMC]
[GeoUtils:RMC] Total amount of duplication 0 duplication
[GeoUtils:RMC]
[GeoUtils:RMC] Total amount of duplication 0 duplication
[GeoUtils:RMC]
[GeoUtils:RMC] Total amount of duplication 0 duplication
[GeoUtils:RMC]
[GeoUtils:RMC] Total amount of duplication 0 duplication
[GeoUtils:RMC]
[GeoUtils:RMC] Total amount of duplication 0 duplication
[GeoUtils:RMC]
[GeoUtils:RMC] Total amount of duplication 0 duplication
[GeoUtils:RMC]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.111785708224785
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.42109184580057, -122.08702507021079)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421091929094544, -122.0870275690302)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000729290945429284, -0.0000024309698005708924)
[GeoUtils:RS] shiftedLocation: LatLng(37.421018916706025, -122.08702750118059)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 8.653874200888446
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 1
[GeoUtils:RS] currentLocation: LatLng(37.421093579404065, -122.08705800867715)
[GeoUtils:RS] _start1: LatLng(37.421019, -122.08703)
[GeoUtils:RS] _end1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42109256404366, -122.08702754786522)
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00007356404366021252, -0.0000024521347796735427)
[GeoUtils:RS] shiftedLocation: LatLng(37.421020015360405, -122.08706046081193)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 11.94023045527367
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 2
[GeoUtils:RS] currentLocation: LatLng(37.42109598407988, -122.08710369751759)
[GeoUtils:RS] _start1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] _end1: LatLng(37.42105, -122.08724)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421086844372155, -122.08704885927129)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00006684437215653816, -0.000011140728702230263)
[GeoUtils:RS] shiftedLocation: LatLng(37.42102913970772, -122.0871148382463)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 14.391902538198476
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 2
[GeoUtils:RS] currentLocation: LatLng(37.42109837277778, -122.0871490827777)
[GeoUtils:RS] _start1: LatLng(37.42102, -122.08706)
[GeoUtils:RS] _end1: LatLng(37.42105, -122.08724)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42108180873875, -122.08704969854354)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00006180873874939152, -0.000010301456455863445)
[GeoUtils:RS] shiftedLocation: LatLng(37.42103656403903, -122.08715938423416)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 25.574636932831467
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 3
[GeoUtils:RS] currentLocation: LatLng(37.42110161512012, -122.08720127614933)
[GeoUtils:RS] _start1: LatLng(37.42105, -122.08724)
[GeoUtils:RS] _end1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.4211053692556, -122.08723356171446)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005536925559823658, -0.000006438285538479249)
[GeoUtils:RS] shiftedLocation: LatLng(37.421046245864524, -122.08720771443487)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 24.9315497465634
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 3
[GeoUtils:RS] currentLocation: LatLng(37.421104292906925, -122.08723894731543)
[GeoUtils:RS] _start1: LatLng(37.42105, -122.08724)
[GeoUtils:RS] _end1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42110368938746, -122.08723375704798)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000053689387456756776, -0.0000062429520113482795)
[GeoUtils:RS] shiftedLocation: LatLng(37.42105060351947, -122.08724519026744)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 26.345810650246186
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 26.345810650246186
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 3
[GeoUtils:RS] currentLocation: LatLng(37.42110745564725, -122.0872834408187)
[GeoUtils:RS] _start1: LatLng(37.42105, -122.08724)
[GeoUtils:RS] _end1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42110170529122, -122.08723398775683)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005170529122011658, -0.000006012243161990227)
[GeoUtils:RS] shiftedLocation: LatLng(37.42105575035603, -122.08728945306186)
[GeoUtils:RS]
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 3
[GeoUtils:RS] currentLocation: LatLng(37.42110745564725, -122.0872834408187)
[GeoUtils:RS] _start1: LatLng(37.42105, -122.08724)
[GeoUtils:RS] _end1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42110170529122, -122.08723398775683)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005170529122011658, -0.000006012243161990227)
[GeoUtils:RS] shiftedLocation: LatLng(37.42105575035603, -122.08728945306186)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 29.488230582255653
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 3
[GeoUtils:RS] currentLocation: LatLng(37.42111130086458, -122.08733184147097)
[GeoUtils:RS] _start1: LatLng(37.42105, -122.08724)
[GeoUtils:RS] _end1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421099946308615, -122.0872341922897)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000499463086143237, -0.00000580771029490279)
[GeoUtils:RS] shiftedLocation: LatLng(37.42106135455597, -122.08733764918126)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 32.969002572549236
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 3
[GeoUtils:RS] currentLocation: LatLng(37.421116371631506, -122.08737571758809)
[GeoUtils:RS] _start1: LatLng(37.42105, -122.08724)
[GeoUtils:RS] _end1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421099915616445, -122.08723419585856)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00004991561644374087, -0.000005804141437693033)
[GeoUtils:RS] shiftedLocation: LatLng(37.42106645601506, -122.08738152172953)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 37.08011185977677
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 40.94116677866363
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 3
[GeoUtils:RS] currentLocation: LatLng(37.421122052925554, -122.08742487644842)
[GeoUtils:RS] _start1: LatLng(37.42105, -122.08724)
[GeoUtils:RS] _end1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42109988122888, -122.08723419985712)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00004988122888249791, -0.000005800142872658398)
[GeoUtils:RS] shiftedLocation: LatLng(37.42107217169667, -122.0874306765913)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 3
[GeoUtils:RS] currentLocation: LatLng(37.42112725936518, -122.08746992650848)
[GeoUtils:RS] _start1: LatLng(37.42105, -122.08724)
[GeoUtils:RS] _end1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421099849715524, -122.08723420352145)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00004984971552346451, -0.000005796478546926664)
[GeoUtils:RS] shiftedLocation: LatLng(37.421077409649655, -122.08747572298702)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 43.24276650818035
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 3
[GeoUtils:RS] currentLocation: LatLng(37.42113296860438, -122.08749516410224)
[GeoUtils:RS] _start1: LatLng(37.42105, -122.08724)
[GeoUtils:RS] _end1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42110258733593, -122.0872338851935)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000052587335929388246, -0.000006114806495816083)
[GeoUtils:RS] shiftedLocation: LatLng(37.42108038126845, -122.08750127890873)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 66.03755902791636
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 66.03755902791636
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 67.01499496225546
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 68.76342263729167
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 4
[GeoUtils:RS] currentLocation: LatLng(37.421177124986784, -122.08769053817915)
[GeoUtils:RS] _start1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] _end1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42116423367207, -122.08764971568255)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00006423367207020192, -0.000020284317457708312)
[GeoUtils:RS] shiftedLocation: LatLng(37.42111289131471, -122.0877108224966)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 4
[GeoUtils:RS] currentLocation: LatLng(37.421177124986784, -122.08769053817915)
[GeoUtils:RS] _start1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] _end1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42116423367207, -122.08764971568255)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00006423367207020192, -0.000020284317457708312)
[GeoUtils:RS] shiftedLocation: LatLng(37.42111289131471, -122.0877108224966)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 83.56220758722311
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 4
[GeoUtils:RS] currentLocation: LatLng(37.42118157695115, -122.08771026666578)
[GeoUtils:RS] _start1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] _end1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421162616824866, -122.08765022626588)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00006261682486297104, -0.00001977373412387351)
[GeoUtils:RS] shiftedLocation: LatLng(37.421118960126286, -122.0877300403999)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 82.65900102644113
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 0
[GeoUtils:RS] end: 4
[GeoUtils:RS] currentLocation: LatLng(37.42118792266154, -122.08773838712062)
[GeoUtils:RS] _start1: LatLng(37.4211, -122.08767)
[GeoUtils:RS] _end1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42116031221428, -122.08765095403763)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000060312214280600074, -0.000019045962375230374)
[GeoUtils:RS] shiftedLocation: LatLng(37.42112761044726, -122.087757433083)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 81.39836503945656
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.42119701058122, -122.08777924701181)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42122015209127, -122.087835058889)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000060152091272414054, -0.000024941111007592554)
[GeoUtils:RS] shiftedLocation: LatLng(37.421136858489945, -122.08780418812282)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 81.26688673458423
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.42120026070924, -122.08779427082106)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421217609893375, -122.08783611297105)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005760989337488809, -0.000023887028959279633)
[GeoUtils:RS] shiftedLocation: LatLng(37.42114265081587, -122.08781815785002)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 82.50049953610275
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.42120684880659, -122.0878247244885)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42121245678955, -122.08783824962386)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000052456789546795335, -0.000021750376149043404)
[GeoUtils:RS] shiftedLocation: LatLng(37.421154392017044, -122.08784647486465)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 85.40641186460483
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 85.40641186460483
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.42121319534037, -122.08785406152145)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42120749263285, -122.08784030793272)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000474926328521974, -0.00001969206728347217)
[GeoUtils:RS] shiftedLocation: LatLng(37.42116570270752, -122.08787375358874)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 88.738775588887
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.42121319534037, -122.08785406152145)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42120749263285, -122.08784030793272)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000474926328521974, -0.00001969206728347217)
[GeoUtils:RS] shiftedLocation: LatLng(37.42116570270752, -122.08787375358874)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 94.06016417882249
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.421221534893, -122.087884333315)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421203898393195, -122.08784179822722)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000043898393194297114, -0.00001820177278943902)
[GeoUtils:RS] shiftedLocation: LatLng(37.421177636499806, -122.08790253508779)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.421234378604105, -122.08792520752121)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42120039634073, -122.08784325029777)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00004039634072938725, -0.000016749702240304032)
[GeoUtils:RS] shiftedLocation: LatLng(37.421193982263375, -122.08794195722345)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 98.6777215931914
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.421246952866724, -122.08796522422656)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42119696775789, -122.08784467190527)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00003696775789308049, -0.00001532809473303587)
[GeoUtils:RS] shiftedLocation: LatLng(37.42120998510883, -122.0879805523213)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 102.89881231321574
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.42126647547926, -122.08802436825893)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421192700814295, -122.08784644112579)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000032700814294628344, -0.00001355887421539137)
[GeoUtils:RS] shiftedLocation: LatLng(37.42123377466496, -122.08803792713314)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 107.90659822986487
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 107.90659822986487
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 121.63449162921438
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.4212846167512, -122.0880728052277)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421191043408676, -122.08784712834276)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00003104340867565725, -0.000012871657247615076)
[GeoUtils:RS] shiftedLocation: LatLng(37.421253573342526, -122.08808567688494)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 120.32673265106655
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 121.36859006565388
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.4212846167512, -122.0880728052277)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421191043408676, -122.08784712834276)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00003104340867565725, -0.000012871657247615076)
[GeoUtils:RS] shiftedLocation: LatLng(37.421253573342526, -122.08808567688494)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.42130107165139, -122.088116739605)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42118954007173, -122.08784775167757)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000029540071729172723, -0.000012248322434516012)
[GeoUtils:RS] shiftedLocation: LatLng(37.42127153157966, -122.08812898792743)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 5
[GeoUtils:RS] currentLocation: LatLng(37.42132257562431, -122.0881668975678)
[GeoUtils:RS] _start1: LatLng(37.42116, -122.08786)
[GeoUtils:RS] _end1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42119014315722, -122.08784750161774)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00003014315721827643, -0.000012498382261583174)
[GeoUtils:RS] shiftedLocation: LatLng(37.42129243246709, -122.08817939595006)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 123.73729412078748
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 6
[GeoUtils:RS] currentLocation: LatLng(37.42134461173373, -122.08821095820893)
[GeoUtils:RS] _start1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] _end1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42136496570418, -122.08825312000486)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000349657041809337, -0.000016879995129670533)
[GeoUtils:RS] shiftedLocation: LatLng(37.42130964602955, -122.08822783820406)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 127.32726501105121
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 6
[GeoUtils:RS] currentLocation: LatLng(37.421361398064136, -122.08824452205026)
[GeoUtils:RS] _start1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] _end1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42136543859164, -122.08825289171438)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000035438591645231554, -0.000017108285618405716)
[GeoUtils:RS] shiftedLocation: LatLng(37.42132595947249, -122.08826163033588)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 131.24551507860616
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 131.24551507860616
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 6
[GeoUtils:RS] currentLocation: LatLng(37.421376564092384, -122.08827484613857)
[GeoUtils:RS] _start1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] _end1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42136586583359, -122.08825268545965)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00003586583359549422, -0.00001731454034370472)
[GeoUtils:RS] shiftedLocation: LatLng(37.42134069825879, -122.08829216067892)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 6
[GeoUtils:RS] currentLocation: LatLng(37.421376564092384, -122.08827484613857)
[GeoUtils:RS] _start1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] _end1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42136586583359, -122.08825268545965)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00003586583359549422, -0.00001731454034370472)
[GeoUtils:RS] shiftedLocation: LatLng(37.42134069825879, -122.08829216067892)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 6
[GeoUtils:RS] currentLocation: LatLng(37.42139322418921, -122.08830160732468)
[GeoUtils:RS] _start1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] _end1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.4213688996811, -122.08825122084359)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000388996811011566, -0.000018779156405912545)
[GeoUtils:RS] shiftedLocation: LatLng(37.42135432450811, -122.08832038648109)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 136.74676893616947
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 139.47589320990045
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 6
[GeoUtils:RS] currentLocation: LatLng(37.42141513335764, -122.08833680011737)
[GeoUtils:RS] _start1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] _end1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42137288939837, -122.08824929477318)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00004288939837238104, -0.000020705226816630784)
[GeoUtils:RS] shiftedLocation: LatLng(37.42137224395927, -122.08835750534419)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 6
[GeoUtils:RS] currentLocation: LatLng(37.42143787933458, -122.08837333707923)
[GeoUtils:RS] _start1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] _end1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42137703150068, -122.08824729513758)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000047031500685079664, -0.000022704862416844662)
[GeoUtils:RS] shiftedLocation: LatLng(37.4213908478339, -122.08839604194165)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 153.6118835487529
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 6
[GeoUtils:RS] currentLocation: LatLng(37.421468981424816, -122.08842378778606)
[GeoUtils:RS] _start1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] _end1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42138250292875, -122.08824465375851)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000052502928753028755, -0.000025346241486090548)
[GeoUtils:RS] shiftedLocation: LatLng(37.42141647849606, -122.08844913402754)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 154.883385889917
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 6
[GeoUtils:RS] currentLocation: LatLng(37.42148420068024, -122.0884486920222)
[GeoUtils:RS] _start1: LatLng(37.42133, -122.08827)
[GeoUtils:RS] _end1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42138509528551, -122.08824340227596)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000055095285510731173, -0.000026597724030352765)
[GeoUtils:RS] shiftedLocation: LatLng(37.42142910539473, -122.08847528974623)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 157.55828356122518
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 157.55828356122518
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 7
[GeoUtils:RS] currentLocation: LatLng(37.42151171529472, -122.0884937159368)
[GeoUtils:RS] _start1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] _end1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42152866070858, -122.08851664208498)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005866070858218109, -0.00004335791501830499)
[GeoUtils:RS] shiftedLocation: LatLng(37.42145305458614, -122.08853707385182)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 7
[GeoUtils:RS] currentLocation: LatLng(37.42151171529472, -122.0884937159368)
[GeoUtils:RS] _start1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] _end1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42152866070858, -122.08851664208498)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005866070858218109, -0.00004335791501830499)
[GeoUtils:RS] shiftedLocation: LatLng(37.42145305458614, -122.08853707385182)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 162.50629358493507
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 163.23718829507695
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 7
[GeoUtils:RS] currentLocation: LatLng(37.42154782802056, -122.08854615076937)
[GeoUtils:RS] _start1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] _end1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42152695118833, -122.08851790564343)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005695118833415336, -0.00004209435657287486)
[GeoUtils:RS] shiftedLocation: LatLng(37.42149087683222, -122.08858824512595)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 7
[GeoUtils:RS] currentLocation: LatLng(37.421571727389, -122.08857735865197)
[GeoUtils:RS] _start1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] _end1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421527489677096, -122.08851750762999)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005748967709706676, -0.00004249237001374695)
[GeoUtils:RS] shiftedLocation: LatLng(37.421514237711904, -122.08861985102199)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 167.64298226572865
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 181.8025005190151
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 181.11039201273312
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 181.2011817265167
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 181.2011817265167
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 7
[GeoUtils:RS] currentLocation: LatLng(37.42160791786121, -122.08862461630277)
[GeoUtils:RS] _start1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] _end1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42152830510293, -122.08851690492392)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005830510293236557, -0.000043095076080135186)
[GeoUtils:RS] shiftedLocation: LatLng(37.42154961275828, -122.08866771137885)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 181.62390115239376
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 184.05848811568117
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 7
[GeoUtils:RS] currentLocation: LatLng(37.42160791786121, -122.08862461630277)
[GeoUtils:RS] _start1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] _end1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42152830510293, -122.08851690492392)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005830510293236557, -0.000043095076080135186)
[GeoUtils:RS] shiftedLocation: LatLng(37.42154961275828, -122.08866771137885)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 187.2996868329553
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 190.62192551035298
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 190.64625981549167
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 7
[GeoUtils:RS] currentLocation: LatLng(37.42161295379956, -122.08863119224945)
[GeoUtils:RS] _start1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] _end1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42152841857022, -122.08851682105681)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000058418570219487265, -0.00004317894318717208)
[GeoUtils:RS] shiftedLocation: LatLng(37.42155453522934, -122.08867437119264)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 193.65348131578654
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 197.18521665546712
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 197.18521665546712
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 213.59404791868917
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 7
[GeoUtils:RS] currentLocation: LatLng(37.421641942679486, -122.08867135002612)
[GeoUtils:RS] _start1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] _end1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42152797043672, -122.08851715228592)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005797043672117752, -0.00004284771408435972)
[GeoUtils:RS] shiftedLocation: LatLng(37.421583972242765, -122.0887141977402)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 214.3893582859389
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 4
[GeoUtils:RS] end: 7
[GeoUtils:RS] currentLocation: LatLng(37.421641942679486, -122.08867135002612)
[GeoUtils:RS] _start1: LatLng(37.42147, -122.08856)
[GeoUtils:RS] _end1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42152797043672, -122.08851715228592)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005797043672117752, -0.00004284771408435972)
[GeoUtils:RS] shiftedLocation: LatLng(37.421583972242765, -122.0887141977402)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 234.7353295319548
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 234.7353295319548
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 7
[GeoUtils:RS] end: 8
[GeoUtils:RS] currentLocation: LatLng(37.421668213851916, -122.08870774301123)
[GeoUtils:RS] _start1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] _end1: LatLng(37.42185, -122.08901)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421695846738544, -122.0887366917496)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005584673854741595, -0.00005330825040061882)
[GeoUtils:RS] shiftedLocation: LatLng(37.42161236711337, -122.08876105126163)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 7
[GeoUtils:RS] end: 8
[GeoUtils:RS] currentLocation: LatLng(37.421668213851916, -122.08870774301123)
[GeoUtils:RS] _start1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] _end1: LatLng(37.42185, -122.08901)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421695846738544, -122.0887366917496)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005584673854741595, -0.00005330825040061882)
[GeoUtils:RS] shiftedLocation: LatLng(37.42161236711337, -122.08876105126163)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 7
[GeoUtils:RS] end: 8
[GeoUtils:RS] currentLocation: LatLng(37.4216853436446, -122.08873147260653)
[GeoUtils:RS] _start1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] _end1: LatLng(37.42185, -122.08901)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421692957815964, -122.08873944935749)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000052957815967147326, -0.00005055064251280328)
[GeoUtils:RS] shiftedLocation: LatLng(37.42163238582863, -122.08878202324904)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 7
[GeoUtils:RS] end: 8
[GeoUtils:RS] currentLocation: LatLng(37.42169539092684, -122.08874539092685)
[GeoUtils:RS] _start1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] _end1: LatLng(37.42185, -122.08901)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42169126335176, -122.08874106680058)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.000051263351764418985, -0.00004893319942311791)
[GeoUtils:RS] shiftedLocation: LatLng(37.42164412757508, -122.08879432412627)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 7
[GeoUtils:RS] end: 8
[GeoUtils:RS] currentLocation: LatLng(37.42170403305291, -122.08875580684197)
[GeoUtils:RS] _start1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] _end1: LatLng(37.42185, -122.08901)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421690582958504, -122.0887417162669)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00005058295850801642, -0.00004828373310772349)
[GeoUtils:RS] shiftedLocation: LatLng(37.421653450094404, -122.08880409057508)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 7
[GeoUtils:RS] end: 8
[GeoUtils:RS] currentLocation: LatLng(37.42173144343256, -122.08878884317882)
[GeoUtils:RS] _start1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] _end1: LatLng(37.42185, -122.08901)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42168842494351, -122.0887437761903)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.00004842494351464666, -0.0000462238097043155)
[GeoUtils:RS] shiftedLocation: LatLng(37.42168301848905, -122.08883506698852)
[GeoUtils:RS]
[GeoUtils:RM]
[GeoUtils:RM] covered dist: 234.7353295319548
[GeoUtils:RM] route length: 2144876.5707896487
[GeoUtils:RM] is finished: false
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 7
[GeoUtils:RS] end: 8
[GeoUtils:RS] currentLocation: LatLng(37.421758068164394, -122.0888209326143)
[GeoUtils:RS] _start1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] _end1: LatLng(37.42185, -122.08901)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.42168632878243, -122.08874577707131)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoUtils:RS] shift: (-0.0000463287824317149, -0.00004422292869321609)
[GeoUtils:RS] shiftedLocation: LatLng(37.42171173938196, -122.08886515554299)
[GeoUtils:RS]
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RMC] You are not on the route
[GeoUtils:RS] removed closing point: 1
[GeoUtils:RS] removed opening point: 2
[GeoUtils:RS] start: 7
[GeoUtils:RS] end: 8
[GeoUtils:RS] currentLocation: LatLng(37.42178259783535, -122.08885049697945)
[GeoUtils:RS] _start1: LatLng(37.42164, -122.08879)
[GeoUtils:RS] _end1: LatLng(37.42185, -122.08901)
[GeoUtils:RS] way 3
[GeoUtils:RS] crossPoint: LatLng(37.421684397565215, -122.08874762050596)
[GeoUtils:RS] way 3
[GeoUtils:RS] way 3
[GeoU

 */