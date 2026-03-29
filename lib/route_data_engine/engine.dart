import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import '../geo_utils.dart';
import '../new_search_rect.dart';
import '../polyline_util.dart';
import '../route_transfer_objects.dart';
import '../side_point.dart';

part 'builder.dart';
part 'serializer.dart';

class RouteDataEngine {
  factory RouteDataEngine({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
    required List<LatLng> wayPoints,
    double searchRectWidth = 10,
    double searchRectExtension = 5,
    double maxDistanceToSidePoint = 100.0,
    int ignoreSimplificationIfLess = 300,
  }) {
    final builder = _Builder(
      route: checkForDuplications(route),
      sp: latLngListToFlat(sidePoints),
      wp: latLngListToFlat(wayPoints),
      srWidth: searchRectWidth,
      srExt: searchRectExtension,
      maxDst: maxDistanceToSidePoint,
      skipSimplify: ignoreSimplificationIfLess,
    )
      ..initSearchRectsAndDistances()
      ..filterAndMapSidePoints();
    return builder.build();
  }

  factory RouteDataEngine.fromRawData({
    required Float64List route,
    required Float64List sidePoints,
    required Float64List wayPoints,
    double searchRectWidth = 10,
    double searchRectExtension = 5,
    double maxDistanceToSidePoint = 100.0,
    int ignoreSimplificationIfLess = 300,
  }) {
    final builder = _Builder(
      route: route,
      sp: sidePoints,
      wp: wayPoints,
      srWidth: searchRectWidth,
      srExt: searchRectExtension,
      maxDst: maxDistanceToSidePoint,
      skipSimplify: ignoreSimplificationIfLess,
    )
      ..initSearchRectsAndDistances()
      ..filterAndMapSidePoints();
    return builder.build();
  }

  RouteDataEngine._({
    required Float64List route,
    required double routeLen,
    required Float64List distFromStart,
    required Float64List segmentsLen,
    required SearchRectBuffer srBuffer,
    required RawSidePointsBuffer alignedSP,
    required SidePointStates spStates,
    required Int64List wpIndices,
    required int nextWPInd,
    required double emaLat,
    required double emaLng,
    required double prevLat,
    required double prevLng,
  })  : _route = route,
        _routeLen = routeLen,
        _distFromStart = distFromStart,
        _segmentsLen = segmentsLen,
        _srBuffer = srBuffer,
        _alignedSP = alignedSP,
        _spStates = spStates,
        _wpIndices = wpIndices,
        _nextWPIndex = nextWPInd,
        _emaLat = emaLat,
        _emaLng = emaLng,
        _prevLat = prevLat,
        _prevLng = prevLng;

  static Future<RouteDataEngine> fromFiles({
    required String corePath,
    required String statePath,
  }) {
    return _Serializer.loadFromFiles(corePath: corePath, statePath: statePath);
  }

  Future<({String core, String state})> initFiles(String directoryPath) async {
    final String corePath = '$directoryPath/route_core.bin';
    final String statePath = '$directoryPath/route_state.bin';

    await _Serializer.saveImmutable(this, corePath);
    await _Serializer.saveMutable(this, statePath);

    return (core: corePath, state: statePath);
  }

  Future<void> updateState(RMState state, String statePath) async {
    _currRPInd = state.currRPInd;
    _nextRPInd = state.nextRPInd;
    _prevRPInd = state.prevRPInd;
    _currSegmInd = state.currSegmInd;
    _prevSegmInd = state.prevSegmInd;
    _nextWPIndex = state.nextWPIndex;
    _isOnRoute = state.isOnRoute;
    _isJump = state.isJump;

    await _Serializer.saveMutable(this, statePath);
  }

  RMConfig createConfig() {
    if (_route.isEmpty) throw StateError('Engine is not initialized.');

    return RMConfig(
      route: _route,
      distFromStart: _distFromStart,
      segmentsLen: _segmentsLen,
      srBuffer: _srBuffer,
      alignedSP: _alignedSP,
      spStates: _spStates,
      wpIndices: _wpIndices,
      routeLen: _routeLen,
      emaLat: _emaLat,
      emaLng: _emaLng,
      prevLat: _prevLat,
      prevLng: _prevLng,
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
  SidePointStates _spStates;

  /// {segment index in the route, distance traveled form start}
  final Float64List _distFromStart;

  /// {segment index in the route, segment length}
  final Float64List _segmentsLen;

  /// Хранит индексы WayPoint внутри массива [_alignedSP].
  final Int64List _wpIndices;

  /// Индекс следующего WayPoint в буфере (заменяет SidePoint? _nextWP)
  int _nextWPIndex;

  int _currRPInd = 0;
  int _nextRPInd = 1;
  int _prevRPInd = 0;
  int _currSegmInd = 0;
  int _prevSegmInd = 0;
  bool _isOnRoute = true;
  bool _isJump = false;

  //TODO: add to [_Serializer]
  double _emaLat;
  double _emaLng;
  double _prevLat;
  double _prevLng;
}
