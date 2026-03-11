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
  }) : _route = _checkForDuplications(route) {
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

      final int simplifiedPointsCount = simplifiedRoute.length ~/ 2;
      final int simplifiedSegmentsCount = simplifiedPointsCount - 1;

      final SearchRectBuffer simplifiedSRBuffer =
          SearchRectBuffer.allocate(simplifiedSegmentsCount);
      final double searchFactor = maxDistanceToSidePoint * 1.5;

      for (int i = 0; i < simplifiedSegmentsCount; i++) {
        final int offset = i * 2;
        simplifiedSRBuffer.calculateAndSet(
          i,
          simplifiedRoute[offset],
          simplifiedRoute[offset + 1],
          simplifiedRoute[offset + 2],
          simplifiedRoute[offset + 3],
          searchFactor,
          searchFactor,
        );
      }

      final List<({int ind, LatLng point, double minDist})> indexedAndCuttedSP =
          _indexingAndCutting(wayPoints, sidePoints, simplifiedSRBuffer,
              simplifiedSegmentsCount, mapping, maxDistanceToSidePoint);
      _aligning(indexedAndCuttedSP);
      _mapping(indexedAndCuttedSP, wayPoints);
    }
  }

  // naming:
  // RP - route point
  // SP - side point
  // WP - way point
  // SR - search rect

  final Float64List _route;
  double _routeLen = 0;
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

  List<({int ind, LatLng point, double minDist})> _indexingAndCutting(
    List<LatLng> wayPoints,
    List<LatLng> sidePoints,
    SearchRectBuffer srBuffer,
    int srSegmentsCount,
    Uint32List mapping,
    double maxDstToSP,
  ) {
    final List<({int ind, LatLng point, double minDist})> passedSP = [];
    final int routePointsCount = _route.length ~/ 2;

    // ----------------- ОБРАБОТКА WAYPOINTS -----------------
    for (final LatLng wp in wayPoints) {
      int bestInd = 0;
      double minDist = double.infinity;
      bool foundInAnySegment = false;

      final double wpLat = wp.latitude;
      final double wpLng = wp.longitude;

      // Фаза 1: Ищем внутри ограничивающих прямоугольников (Broad-Phase)
      for (int i = 0; i < srSegmentsCount; i++) {
        if (srBuffer.isPointInRect(i, wpLat, wpLng)) {
          foundInAnySegment = true;

          final int start = mapping[i];
          final int end = mapping[i + 1];

          for (int rpInd = start; rpInd <= end; rpInd++) {
            final int offset = rpInd * 2;
            final double dist = getDistanceRaw(
                wpLat, wpLng, _route[offset], _route[offset + 1]);

            if (dist < minDist) {
              minDist = dist;
              bestInd = rpInd;
            }
          }
        }
      }

      // Фаза 2: Точка далеко (река/лес). Fallback на линейный поиск по всему маршруту
      if (!foundInAnySegment) {
        int currentOffset = 0;
        for (int rpInd = 0; rpInd < routePointsCount; rpInd++) {
          final double dist = getDistanceRaw(
              wpLat, wpLng, _route[currentOffset], _route[currentOffset + 1]);

          if (dist < minDist) {
            minDist = dist;
            bestInd = rpInd;
          }
          currentOffset += 2;
        }
      }

      passedSP.add((ind: bestInd, point: wp, minDist: minDist));
    }

    // ----------------- ОБРАБОТКА SIDEPOINTS -----------------
    for (final LatLng sp in sidePoints) {
      int bestInd = -1;
      double minDist = double.infinity;

      final double spLat = sp.latitude;
      final double spLng = sp.longitude;

      // SidePoints ищутся ТОЛЬКО если попали в буфер (поисковые прямоугольники)
      for (int i = 0; i < srSegmentsCount; i++) {
        if (srBuffer.isPointInRect(i, spLat, spLng)) {
          final int start = mapping[i];
          final int end = mapping[i + 1];

          for (int rpInd = start; rpInd <= end; rpInd++) {
            final int offset = rpInd * 2;
            final double dist = getDistanceRaw(
                spLat, spLng, _route[offset], _route[offset + 1]);

            if (dist <= maxDstToSP && dist < minDist) {
              minDist = dist;
              bestInd = rpInd;
            }
          }
        }
      }

      if (bestInd != -1) {
        passedSP.add((ind: bestInd, point: sp, minDist: minDist));
      }
    }

    return passedSP;
  }

  void _aligning(List<({int ind, LatLng point, double minDist})> indexedSP) {
    indexedSP.sort((a, b) {
      final indCompare =
          (a.ind == 0 ? -1 : a.ind).compareTo(b.ind == 0 ? -1 : b.ind);

      if (indCompare != 0) return indCompare;
      return a.ind == 0
          ? -a.minDist.compareTo(b.minDist)
          : a.minDist.compareTo(b.minDist);
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
