import 'dart:math';
import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';
import 'new_search_rect.dart';
import 'polyline_util.dart';
import 'side_point.dart';

/// Route manager data access object
class RouteManagerDAO {
  RouteManagerDAO({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
    required List<LatLng> wayPoints,
    double searchRectWidth = 10,
    double searchRectExtension = 5,
    double maxDistanceToSidePoint = 100.0,
    int ignoreSimplificationIfLess = 300,
  })  : _route = _checkForDuplications(route),
        _routeLen = 0 {
    if (_route.length < 4) throw ArgumentError('Your route length less than 2');

    final int pointsCount = _route.length ~/ 2;
    final int segmentsCount = pointsCount - 1;
    _distFromStart = Float64List(pointsCount);
    _segmentsLen = Float64List(segmentsCount);

    int pointIndex = 0;
    final int maxOffset = _route.length - 2;
    _srBuffer = SearchRectBuffer.allocate(segmentsCount);

    for (int offset = 0; offset < maxOffset; offset += 2) {
      final double lat1 = _route[offset];
      final double lon1 = _route[offset + 1];
      final double lat2 = _route[offset + 2];
      final double lon2 = _route[offset + 3];

      final double dist = getDistanceRaw(lat1, lon1, lat2, lon2);
      _distFromStart[pointIndex] = _routeLen;
      _segmentsLen[pointIndex] = dist;
      _routeLen += dist;

      _srBuffer.calculateAndSet(
        pointIndex,
        lat1,
        lon1,
        lat2,
        lon2,
        searchRectWidth,
        searchRectExtension,
      );

      pointIndex++;
    }
    _distFromStart[pointIndex] = _routeLen;

    if (sidePoints.isNotEmpty || wayPoints.isNotEmpty) {
      final double tolerance = maxDistanceToSidePoint / 2;
      final rdpResult = rdpRouteSimplifierRaw(
        _route,
        tolerance,
        ignoreIfLess: ignoreSimplificationIfLess,
      );

      final Float64List simplifiedRoute = rdpResult.route;
      final Uint32List mapping = rdpResult.mapping;

      final int simpPointsAmount = simplifiedRoute.length ~/ 2;
      final int simpSegAmount = simpPointsAmount - 1;

      final SearchRectBuffer simpSRBuff =
          SearchRectBuffer.allocate(simpSegAmount);
      final double searchFactor = maxDistanceToSidePoint * 1.5;

      for (int i = 0; i < simpSegAmount; i++) {
        final int offset = i * 2;
        simpSRBuff.calculateAndSet(
          i,
          simplifiedRoute[offset],
          simplifiedRoute[offset + 1],
          simplifiedRoute[offset + 2],
          simplifiedRoute[offset + 3],
          searchFactor,
          searchFactor,
        );
      }

      final List<({int ind, LatLng point, double minDist})> filteredSP =
          _filtering(wayPoints, sidePoints, simpSRBuff, simpSegAmount, mapping,
              maxDistanceToSidePoint);
      _aligning(filteredSP);
      _mapping(filteredSP, wayPoints);
    }
  }

  // naming:
  // RP - route point
  // SP - side point
  // WP - way point
  // SR - search rect

  final Float64List _route;
  double _routeLen;
  int _currRPInd = 0;
  int _nextRPInd = 1;
  int _prevRPInd = 0;
  int _currSegmInd = 0;
  int _prevSegmInd = 0;
  bool _isOnRoute = true;
  bool _isJump = false;

  /// Буфер прямоугольников поиска вместо Map<int, SearchRect>
  SearchRectBuffer _srBuffer;

  /// {index of aligned side point, side point}
  /// ``````
  /// In function works with a beginning of segment.
  final Map<int, SidePoint> _alignedSP = {};

  /// {segment index in the route, distance traveled form start}
  Float64List _distFromStart;

  /// {segment index in the route, segment length}
  Float64List _segmentsLen;

  SidePoint? _nextWP;
  List<SidePoint> _wpList = [];

  //-----------------------------Methods----------------------------------------

  /// Checks the path for duplicate coordinates, and returns a flat array
  /// where even indices are latitudes and odd indices are longitudes
  /// [lat0, lng0, lat1, lng1, ...].
  static Float64List _checkForDuplications(List<LatLng> route) {
    if (route.isEmpty) return Float64List(0);

    int uniqueCount = 1;
    for (int i = 1; i < route.length; i++) {
      if (route[i] != route[i - 1]) uniqueCount++;
    }

    final Float64List cleanRoute = Float64List(uniqueCount * 2);
    cleanRoute[0] = route[0].latitude;
    cleanRoute[1] = route[0].longitude;
    int ptr = 2;

    for (int i = 1; i < route.length; i++) {
      if (route[i] != route[i - 1]) {
        cleanRoute[ptr++] = route[i].latitude;
        cleanRoute[ptr++] = route[i].longitude;
      }
    }
    return cleanRoute;
  }

  /// Calculates the squared angular distance between two points.
  /// Returns radians squared. Used for ultra-fast distance comparisons
  /// without the overhead of sqrt() and Earth radius multiplication.
  @pragma('vm:prefer-inline')
  double _getDistanceRadSq(double lat1, double lon1, double lat2, double lon2) {
    final double rLat1 = lat1 * deg2rad;
    final double rLon1 = lon1 * deg2rad;
    final double rLat2 = lat2 * deg2rad;
    final double rLon2 = lon2 * deg2rad;

    final double dLat = rLat2 - rLat1;
    final double dLon = rLon2 - rLon1;

    final double averageLat = (rLat1 + rLat2) * 0.5;
    final double x = dLon * cos(averageLat);

    return (x * x) + (dLat * dLat);
  }

  List<({int ind, LatLng point, double minDist})> _filtering(
    List<LatLng> wayPoints,
    List<LatLng> sidePoints,
    SearchRectBuffer srBuffer,
    int srSegAmount,
    Uint32List mapping,
    double maxDstToSP,
  ) {
    final List<({int ind, LatLng point, double minDist})> passedSP = [];
    final int routePointsCount = _route.length ~/ 2;
    double minDistRadSq;
    double distRadSq;
    int bestInd;

    // Предарасчет констант для быстрого сравнения квадратов (в радианах)
    final double maxDstRad = maxDstToSP / earthRadiusInMeters;
    final double maxDstRadSq = maxDstRad * maxDstRad;

    // --- ОБРАБОТКА WAYPOINTS ---
    for (final LatLng wp in wayPoints) {
      bool foundInAnySegment = false;
      minDistRadSq = double.infinity;
      bestInd = 0;

      final double wpLat = wp.latitude;
      final double wpLng = wp.longitude;

      for (int i = 0; i < srSegAmount; i++) {
        if (!srBuffer.isPointInRect(i, wpLat, wpLng)) continue;

        foundInAnySegment = true;
        final int start = mapping[i];
        final int end = mapping[i + 1];

        int offset = start * 2;
        for (int rpInd = start; rpInd <= end; rpInd++) {
          distRadSq = _getDistanceRadSq(
              wpLat, wpLng, _route[offset], _route[offset + 1]);

          if (distRadSq < minDistRadSq) {
            minDistRadSq = distRadSq;
            bestInd = rpInd;
          }
          offset += 2;
        }
      }

      if (!foundInAnySegment) {
        int offset = 0;
        for (int rpInd = 0; rpInd < routePointsCount; rpInd++) {
          final double distSq = _getDistanceRadSq(
              wpLat, wpLng, _route[offset], _route[offset + 1]);

          if (distSq < minDistRadSq) {
            minDistRadSq = distSq;
            bestInd = rpInd;
          }
          offset += 2;
        }
      }

      // Возвращаем физические метры только при сохранении
      final double finalDistMeters = earthRadiusInMeters * sqrt(minDistRadSq);
      passedSP.add((ind: bestInd, point: wp, minDist: finalDistMeters));
    }

    // --- ОБРАБОТКА SIDEPOINTS ---
    for (final LatLng sp in sidePoints) {
      minDistRadSq = double.infinity;
      bestInd = -1;

      final double spLat = sp.latitude;
      final double spLng = sp.longitude;

      for (int i = 0; i < srSegAmount; i++) {
        if (!srBuffer.isPointInRect(i, spLat, spLng)) continue;

        final int start = mapping[i];
        final int end = mapping[i + 1];

        int offset = start * 2;
        for (int rpInd = start; rpInd <= end; rpInd++) {
          distRadSq = _getDistanceRadSq(
              spLat, spLng, _route[offset], _route[offset + 1]);

          // Сравниваем сырые квадраты
          if (distRadSq <= maxDstRadSq && distRadSq < minDistRadSq) {
            minDistRadSq = distRadSq;
            bestInd = rpInd;
          }
          offset += 2;
        }
      }

      if (bestInd != -1) {
        final double finalDistMeters = earthRadiusInMeters * sqrt(minDistRadSq);
        passedSP.add((ind: bestInd, point: sp, minDist: finalDistMeters));
      }
    }

    return passedSP;
  }

  void _aligning(List<({int ind, LatLng point, double minDist})> indexedSP) {
    indexedSP.sort((a, b) {
      final int indCompare = a.ind.compareTo(b.ind);
      if (indCompare != 0) return indCompare;
      if (a.ind == 0) return b.minDist.compareTo(a.minDist);
      return a.minDist.compareTo(b.minDist);
    });
  }

  void _mapping(List<({int ind, LatLng point, double minDist})> alignedSPData,
      List<LatLng> wayPoints) {
    int index = 0;
    bool firstNextFlag = true;

    for (final ({int ind, LatLng point, double minDist}) sp in alignedSPData) {
      final int ind = sp.ind;
      final LatLng sidePoint = sp.point;
      final double minDist = sp.minDist;

      final bool isLast = ind == _route.length - 1;
      final LatLng nextP = isLast ? _route[ind] : _route[ind + 1];
      final LatLng closestP = isLast ? _route[ind - 1] : _route[ind];

      final double skew = skewProduction(closestP, nextP, sidePoint);
      final PointPosition position =
          skew <= 0 ? PointPosition.right : PointPosition.left;

      final PointState state = ind <= _currRPInd
          ? PointState.past
          : firstNextFlag && ind > _currRPInd
              ? (() {
                  firstNextFlag = false;
                  return PointState.next;
                })()
              : PointState.onWay;

      final double dist = _distFromStart[ind]! + minDist;

      _alignedSP[index] = SidePoint(
          point: sidePoint,
          routeInd: ind,
          position: position,
          state: state,
          dist: dist);
      index++;

      if (wayPoints.contains(sidePoint)) {
        _wpList.add(SidePoint(
            point: sidePoint,
            routeInd: ind,
            position: position,
            state: state,
            dist: dist));
      }
    }
    _wpList = _wpList.reversed.toList();
    if (_wpList.isNotEmpty) _nextWP = _wpList.last;
  }
}
