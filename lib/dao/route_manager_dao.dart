import 'dart:math';
import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import '../geo_utils.dart';
import '../new_search_rect.dart';
import '../polyline_util.dart';
import '../side_point.dart';

part 'route_manager_builder.dart';
part 'route_manager_serializer.dart';

/// Route manager data access object
class RouteManagerDAO {
  factory RouteManagerDAO({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
    required List<LatLng> wayPoints,
    double searchRectWidth = 10,
    double searchRectExtension = 5,
    double maxDistanceToSidePoint = 100.0,
    int ignoreSimplificationIfLess = 300,
    int historySize = 3,
  }) {
    final builder = _RouteManagerBuilder(
      route: checkForDuplications(route),
      sp: latLngListToFlat(sidePoints),
      wp: latLngListToFlat(wayPoints),
      srWidth: searchRectWidth,
      srExt: searchRectExtension,
      maxDst: maxDistanceToSidePoint,
      skipSimplify: ignoreSimplificationIfLess,
      historySize: historySize,
    )
      ..initSearchRectsAndDistances()
      ..filterAndMapSidePoints();
    return builder.build();
  }

  factory RouteManagerDAO.fromRawData({
    required Float64List route,
    required Float64List sidePoints,
    required Float64List wayPoints,
    double searchRectWidth = 10,
    double searchRectExtension = 5,
    double maxDistanceToSidePoint = 100.0,
    int ignoreSimplificationIfLess = 300,
    int historySize = 3,
  }) {
    final builder = _RouteManagerBuilder(
      route: route,
      sp: sidePoints,
      wp: wayPoints,
      srWidth: searchRectWidth,
      srExt: searchRectExtension,
      maxDst: maxDistanceToSidePoint,
      skipSimplify: ignoreSimplificationIfLess,
      historySize: historySize,
    )
      ..initSearchRectsAndDistances()
      ..filterAndMapSidePoints();
    return builder.build();
  }

  RouteManagerDAO._({
    required Float64List route,
    required double routeLen,
    required Float64List distFromStart,
    required Float64List segmentsLen,
    required SearchRectBuffer srBuffer,
    required RawSidePointsBuffer alignedSP,
    required List<int> wpIndices,
    required int nextWPInd,
    required int historySize,
  })  : _route = route,
        _routeLen = routeLen,
        _distFromStart = distFromStart,
        _segmentsLen = segmentsLen,
        _srBuffer = srBuffer,
        _alignedSP = alignedSP,
        _wpIndices = wpIndices,
        _nextWPIndex = nextWPInd,
        _historySize = historySize;

  static Future<RouteManagerDAO> fromFile(String filePath) async {
    // TODO: Подключить модули записи и чтения SoA.
    return RouteManagerDAO._(
      route: Float64List(0),
      routeLen: 0.0,
      distFromStart: Float64List(0),
      segmentsLen: Float64List(0),
      srBuffer: SearchRectBuffer.allocate(0),
      alignedSP: RawSidePointsBuffer.empty(),
      wpIndices: [],
      nextWPInd: -1,
      historySize: 3,
    );
  }

  /// Checks the path for duplicate coordinates, and returns a flat array
  /// where even indices are latitudes and odd indices are longitudes
  /// [lat0, lng0, lat1, lng1, ...].
  static Float64List checkForDuplications(List<LatLng> route) {
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

  static Float64List latLngListToFlat(List<LatLng> points) {
    if (points.isEmpty) return Float64List(0);
    final flat = Float64List(points.length * 2);
    for (int i = 0; i < points.length; i++) {
      flat[i * 2] = points[i].latitude;
      flat[i * 2 + 1] = points[i].longitude;
    }
    return flat;
  }

  // naming:
  // RP - route point
  // SP - side point
  // WP - way point
  // SR - search rect

  final Float64List _route;
  final double _routeLen;

  /// Буфер прямоугольников поиска вместо Map<int, SearchRect>
  final SearchRectBuffer _srBuffer;

  /// Flat buffer DoD-контейнер, заменяющий старый Map<int, SidePoint>.
  /// {index of aligned side point, side point}
  /// In function works with a beginning of segment.
  final RawSidePointsBuffer _alignedSP;

  /// {segment index in the route, distance traveled form start}
  final Float64List _distFromStart;

  /// {segment index in the route, segment length}
  final Float64List _segmentsLen;

  /// Хранит индексы WayPoint внутри массива [_alignedSP].
  final List<int> _wpIndices;

  /// Индекс следующего WayPoint в буфере (заменяет SidePoint? _nextWP)
  final int _nextWPIndex;

  /// Determines the size of the coefficient list for the weighted vector
  /// and the number of previous positions to store.
  final int _historySize;

  int _currRPInd = 0;
  int _nextRPInd = 1;
  int _prevRPInd = 0;
  int _currSegmInd = 0;
  int _prevSegmInd = 0;
  bool _isOnRoute = true;
  bool _isJump = false;
}
