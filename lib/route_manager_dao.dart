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
  })  : _alignedSP = RawSidePointsBuffer.empty(),
        _route = _checkForDuplications(route),
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

      final Set<LatLng> wpSet = wayPoints.toSet();

      _filtering(wayPoints, sidePoints, simpSRBuff, simpSegAmount, mapping,
          maxDistanceToSidePoint, _alignedSP);

      _alignedSP.align();
      _mapping(_alignedSP, wpSet);
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
  final RawSidePointsBuffer _alignedSP;

  /// {segment index in the route, distance traveled form start}
  Float64List _distFromStart;

  /// {segment index in the route, segment length}
  Float64List _segmentsLen;
  List<int> _wpIndices = [];
  int _nextWPIndex = -1;

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

  void _filtering(
    List<LatLng> wayPoints,
    List<LatLng> sidePoints,
    SearchRectBuffer srBuffer,
    int srSegAmount,
    Uint32List mapping,
    double maxDstToSP,
    RawSidePointsBuffer passedSP,
  ) {
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
          distRadSq = getDistanceRadSq(
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
          final double distSq = getDistanceRadSq(
              wpLat, wpLng, _route[offset], _route[offset + 1]);

          if (distSq < minDistRadSq) {
            minDistRadSq = distSq;
            bestInd = rpInd;
          }
          offset += 2;
        }
      }

      final double finalDistMeters = earthRadiusInMeters * sqrt(minDistRadSq);
      passedSP.add(RawSidePoint.addUnmapped(
        lat: wpLat,
        lng: wpLng,
        dist: finalDistMeters,
        routeInd: bestInd,
      ));
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
          distRadSq = getDistanceRadSq(
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

        passedSP.add(RawSidePoint.addUnmapped(
          lat: spLat,
          lng: spLng,
          dist: finalDistMeters,
          routeInd: bestInd,
        ));
      }
    }
  }

  void _mapping(RawSidePointsBuffer alignedSPData, Set<LatLng> wpSet) {
    bool firstNextFlag = true;

    // final int routePointsAmount = _route.length ~/ 2;
    // final int lastPointInd = (_route.length ~/ 2) - 1;
    final int secondToLastIndex = (_route.length ~/ 2) - 2;

    for (int i = 0; i < alignedSPData.length; i++) {
      final RawSidePoint sp = alignedSPData[i];
      final int ind = sp.routeInd;

      // 1. Вычисляем индексы соседних точек без аллокаций LatLng
      final int closestInd = min(ind, secondToLastIndex);
      final int nextInd = closestInd + 1;

      final int closestOffset = closestInd * 2;
      final int nextOffset = nextInd * 2;

      final double closestLat = _route[closestOffset];
      final double closestLng = _route[closestOffset + 1];

      final double nextLat = _route[nextOffset];
      final double nextLng = _route[nextOffset + 1];

      // 2. Считаем Skew напрямую через примитивы
      final double skew = skewProductionRaw(
        closestLat,
        closestLng,
        nextLat,
        nextLng,
        sp.lat,
        sp.lng,
      );

      if (skew <= 0) {
        sp.position = PointPosition.right;
      } else {
        sp.position = PointPosition.left;
      }

      if (ind <= _currRPInd) {
        sp.state = PointState.past;
      } else if (firstNextFlag) {
        sp.state = PointState.next;
        firstNextFlag = false;
      } else {
        sp.state = PointState.onWay;
      }

      sp.dist = _distFromStart[ind] + sp.dist;

      final LatLng pointLatLng = LatLng(sp.lat, sp.lng);
      if (wpSet.contains(pointLatLng)) _wpIndices.add(i);
    }

    _wpIndices = _wpIndices.reversed.toList();
    if (_wpIndices.isNotEmpty) _nextWPIndex = _wpIndices.last;
  }
}
