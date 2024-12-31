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
    print('[GeoUtils:RouteSimplifier] mapping length ${mapping.length}');
    //print('[GeoUtils:RouteSimplifier] original route length ${_route.length}');
    //print('[GeoUtils:RouteSimplifier] cutted route length ${route.length}');
    print('[GeoUtils:RouteSimplifier] indexExtension $indexExtension');
    final List<LatLng> resultPath = [];
    bool insideBounds = false;
    //содержит пары входа и выхода из области видимости function
    // проверяется по четности нечетности количества элементов в списке
    List<int> replacementsList = isNull ? [] : [0, 1];

    int iteratorStart = isNull ? 0 : 2;
    for (int i = iteratorStart; i < route.length; i++) {
      if (bounds.contains(route[i])) {
        if (insideBounds == false) {
          replacementsList.add(i);
          print('[GeoUtils:RouteSimplifier] $i - IN');
        }
        insideBounds = true;
      } else {
        if (insideBounds == true) {
          replacementsList.add(i);
          print('[GeoUtils:RouteSimplifier] $i - OUT');
        }
        insideBounds = false;
      }
      print('[GeoUtils:RouteSimplifier] $i - ${route[i]}');
      //i++;
    }

    if (replacementsList.isEmpty) {
      return route;
    } else if (replacementsList.length.isOdd) {
      replacementsList.add(route.length - 1);
    } else if (isNull) {
      resultPath.addAll(route.sublist(0, replacementsList.first));
    }
    replacementsList = _segmentConnector(replacementsList);
    print('[GeoUtils:RouteSimplifier] replacementsList $replacementsList');

    for (int i = 0; i < (replacementsList.length - 1); i += 2) {
      final int startIndex = replacementsList[i];
      print('[GeoUtils:RouteSimplifier] startIndex $startIndex');
      final int endIndex = replacementsList[i + 1];
      print('[GeoUtils:RouteSimplifier] endIndex $endIndex');
      print(
          '[GeoUtils:RouteSimplifier] extended startIndex ${startIndex + indexExtension}');
      print(
          '[GeoUtils:RouteSimplifier] extended endIndex ${endIndex + indexExtension}');
      int originalStartIndex = mapping[startIndex + indexExtension]!;
      //print('[GeoUtils:RouteSimplifier] originalStartIndex $originalStartIndex');
      final int originalEndIndex = mapping[endIndex + indexExtension]!;
      //print('[GeoUtils:RouteSimplifier] originalEndIndex $originalEndIndex');

      if (i == 0 && !isNull) {
        final LatLng shiftedLocation = _currentLocationCutter(
          currentLocation,
          originalStartIndex,
          originalRouteRouteManager.nextRoutePointIndex,
        );
        resultPath.add(shiftedLocation);
        shiftedRouteRouteManager.updateCurrentLocation(shiftedLocation);
        originalStartIndex = originalRouteRouteManager.nextRoutePointIndex;
        //print('[GeoUtils:RouteSimplifier] next point $originalStartIndex');
      }
      resultPath.addAll(_route.sublist(originalStartIndex, originalEndIndex));

      if (i + 2 < replacementsList.length) {
        resultPath.addAll(route.sublist(endIndex, replacementsList[i + 2]));
      }
    }

    resultPath.addAll(route.sublist(replacementsList.last));

    print('[GeoUtils:RouteSimplifier]');
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
    //print('[GeoUtils:RouteSimplifier] start: $start');
    //print('[GeoUtils:RouteSimplifier] end: $end');

    LatLng _start = _route[end - 1];
    LatLng _end = _route[end];
    //print('[GeoUtils:RouteSimplifier] currentLocation: $currentLocation');
    //print('[GeoUtils:RouteSimplifier] _start1: $_start');
    //print('[GeoUtils:RouteSimplifier] _end1: $_end');

    final LatLng crossPoint1 = _findCrossPoint(currentLocation, _start, _end);
    //print('[GeoUtils:RouteSimplifier] crossPoint1: $crossPoint1');

    late (double, double) shift;
    late (double, double) shift1;
    late (double, double) shift2;
    late (double, double) shift3;

    // current shift
    shift1 = (
      _start.latitude - crossPoint1.latitude,
      _start.longitude - crossPoint1.longitude,
    );

    if (end - 2 >= 0) {
      _end = _route[end - 1];
      _start = _route[end - 2];
      //print('[GeoUtils:RouteSimplifier] _start2: $_start');
      //print('[GeoUtils:RouteSimplifier] _end2: $_end');

      final LatLng crossPoint2 = _findCrossPoint(currentLocation, _start, _end);
      //print('[GeoUtils:RouteSimplifier] crossPoint2: $crossPoint2');

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
      //print('[GeoUtils:RouteSimplifier] _start3: $_start');
      //print('[GeoUtils:RouteSimplifier] _end3: $_end');

      final LatLng crossPoint3 = _findCrossPoint(currentLocation, _start, _end);
      //print('[GeoUtils:RouteSimplifier] crossPoint3: $crossPoint3');

      // previous shift
      shift3 = (
        _start.latitude - crossPoint3.latitude,
        _start.longitude - crossPoint3.longitude,
      );
    } else {
      shift3 = shift1;
    }

    /*
    shift = (
      0.5 * shift1.$1 + 0.25 * shift2.$1 + 0.25 * shift3.$1,
      0.5 * shift1.$2 + 0.25 * shift2.$2 + 0.25 * shift3.$2,
    );

     */

    shift = (shift1.$1, shift1.$2);

    shiftedLocation = LatLng(
      currentLocation.latitude + shift.$1,
      currentLocation.longitude + shift.$2,
    );
    //print('[GeoUtils:RouteSimplifier] shiftedLocation: $shiftedLocation');

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
      return LatLng(c / b, _c / b);
    } else if (a != 0 && b == 0) {
      return LatLng(-(c / a), _c / a);
    } else if (a != 0 && b != 0) {
      final double y = (b * c + _c * a) / (b * b + a * a);
      final double x = (b / a) * y - (c / a);

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
