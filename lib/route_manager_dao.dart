import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';
import 'polyline_util.dart';
import 'search_rect.dart';
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
  })  : _maxDistToSP = maxDistanceToSidePoint,
        _route = _checkForDuplications(route) {
    if (_route.length < 4) throw ArgumentError('Your route length less than 2');

    final int pointsCount = _route.length ~/ 2;
    final int segmentsCount = pointsCount - 1;
    _distFromStart = Float64List(pointsCount);
    _segmentsLen = Float64List(segmentsCount);

    int pointIndex = 0;
    final int maxOffset = _route.length - 2;

    for (int offset = 0; offset < maxOffset; offset += 2) {
      final double lat1 = _route[offset];
      final double lon1 = _route[offset + 1];
      final double lat2 = _route[offset + 2];
      final double lon2 = _route[offset + 3];

      final double dist = getDistanceRaw(lat1, lon1, lat2, lon2);
      _distFromStart[pointIndex] = _routeLen;
      _segmentsLen[pointIndex] = dist;
      _routeLen += dist;

      _srMap[pointIndex] = SearchRect(
        start: LatLng(lat1, lon1),
        end: LatLng(lat2, lon2),
        rectWidth: searchRectWidth,
        rectExt: searchRectExtension,
      );

      pointIndex++;
    }
    // Закрываем N-ную точку (конец последнего сегмента)
    _distFromStart[pointIndex] = _routeLen;
    // By default we think that we are starting at the beginning of the route
    _currRP = _route[0];
    _nextRP = _route[1];

    if (sidePoints.isNotEmpty || wayPoints.isNotEmpty) {
      final Map<int, int> mapping = {};
      final double tolerance = _maxDistToSP / 2;
      final List<LatLng> simplifiedRoute = rdpRouteSimplifier(_route, tolerance,
          ignoreIfLess: ignoreSimplificationIfLess, mapping: mapping);
      final Map<int, SearchRect> simplifiedSRMap = {};
      final double searchFactor = _maxDistToSP * 1.5;

      for (int i = 0; i < (simplifiedRoute.length - 1); i++) {
        simplifiedSRMap[i] = SearchRect(
          start: simplifiedRoute[i],
          end: simplifiedRoute[i + 1],
          rectWidth: searchFactor,
          rectExt: searchFactor,
        );
      }

      final List<({int ind, LatLng point, double minDist})> indexedAndCuttedSP =
          _indexingAndCutting(wayPoints, sidePoints, simplifiedSRMap, mapping);
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
  late LatLng _currRP;
  late LatLng _nextRP;
  late LatLng _prevRP;
  int _currRPInd = 0;
  int _nextRPInd = 1;
  int _prevRPInd = 0;
  int _currSegmInd = 0;
  int _prevSegmInd = 0;
  bool _isOnRoute = true;
  bool _isJump = false;
  final double _maxDistToSP;

  /// {segment index in the route, search rect}
  final Map<int, SearchRect> _srMap = {};

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
      Map<int, SearchRect> srMap,
      Map<int, int> mapping) {
    final List<({int ind, LatLng point, double minDist})> passedSP = [];
    int wpStartIndex = 0;

    for (final LatLng wp in wayPoints) {
      int ind = wpStartIndex;
      double minDist = double.infinity;
      final List<int> insideSegm = [];

      for (int i = 0; i < srMap.length; i++) {
        final SearchRect sr = srMap[i]!;
        if (sr.isPointInRect(wp)) insideSegm.add(i);
      }

      for (final int segmInd in insideSegm) {
        final int start = mapping[segmInd]!;
        final int end = mapping[segmInd + 1]!;

        for (int rpInd = start; rpInd <= end; rpInd++) {
          final double dist = getDistance(wp, _route[rpInd]);
          if (dist < minDist) {
            minDist = dist;
            ind = rpInd;
            wpStartIndex = rpInd;
          }
        }
      }

      if (minDist == double.infinity) {
        for (int i = 0; i < _route.length; i++) {
          final double dist = getDistance(wp, _route[i]);
          if (dist < minDist) {
            minDist = dist;
            ind = i;
            wpStartIndex = i;
          }
        }
      }
      passedSP.add((ind: ind, point: wp, minDist: minDist));
    }

    for (final LatLng sp in sidePoints) {
      // index of closes route point
      int ind = -1;
      double minDist = double.infinity;
      final List<int> insideSegm = [];

      for (int i = 0; i < srMap.length; i++) {
        final SearchRect sr = srMap[i]!;
        if (sr.isPointInRect(sp)) insideSegm.add(i);
      }

      if (insideSegm.isNotEmpty) {
        for (final int segmInd in insideSegm) {
          final int start = mapping[segmInd]!;
          final int end = mapping[segmInd + 1]!;

          for (int rpInd = start; rpInd <= end; rpInd++) {
            final dist = getDistance(sp, _route[rpInd]);
            if (dist <= _maxDistToSP && dist < minDist) {
              minDist = dist;
              ind = rpInd;
            }
          }
        }
        if (ind != -1) passedSP.add((ind: ind, point: sp, minDist: minDist));
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
