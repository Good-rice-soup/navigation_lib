import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import '../geo_utils.dart';
import '../io/binary_reader.dart';
import '../io/binary_writer.dart';
import '../new_search_rect.dart';
import '../polyline_util.dart';
import '../route_manager_new.dart';
import '../route_transfer_objects.dart';
import '../side_point.dart';

part 'builder.dart';
part 'io_mutex.dart';
part 'serializer.dart';

/// Persistent storage and in-memory representation of a single route's
/// geographic data (immutable) and navigation progress (mutable).
///
/// Holds two categories of data:
/// * **Immutable** — route geometry, search rectangles, side/way points.
///   Set once at construction time and never modified.
/// * **Mutable** — navigation progress (current segment, covered distance,
///   EMA-smoothed position, side point states). Updated on every GPS tick
///   via [updateState] and persisted to disk through an internal
///   [_IoMutex].
///
/// Typically paired with [RouteManager], which runs the actual navigation
/// math and produces [RMState] objects to feed back into [updateState].
///
/// File I/O contract:
/// * [initFiles] — writes both immutable and mutable dumps to disk.
/// * [fromFiles] — reconstructs the engine from a pair of dump files.
/// * [updateState] with a path — queues a non-blocking atomic write of the
///   mutable state. Safe to call at any frequency.
/// * [flush] — awaitable barrier; completes when all pending writes are done.
///   Call before moving, renaming, or deleting the dump files.
class RouteDataEngine {
  /// Creates a new engine from high-level [LatLng] lists. Internally builds
  /// search rectangles, filters and aligns side points, and computes segment
  /// distances. Use [RouteDataEngine.fromRawData] to skip [LatLng] conversion
  /// when raw [Float64List] arrays are already available.
  ///
  /// [sidePoints] must not contain duplicates — duplicate entries will produce
  /// multiple internal records sharing the same coordinates, causing state
  /// updates (e.g. deletion) to affect only the first match.
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

  /// Same as the default constructor, but accepts pre-flattened [Float64List]
  /// arrays directly. Use when data arrives via [TransferableTypedData] from
  /// another isolate, or when raw arrays are already available. Convert
  /// [LatLng] lists beforehand with [checkForDuplications] (for the route)
  /// and [latLngListToFlat] (for side/way points).
  ///
  /// [sidePoints] must not contain duplicates — duplicate entries will produce
  /// multiple internal records sharing the same coordinates, causing state
  /// updates (e.g. deletion) to affect only the first match.
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
    required double emaLat,
    required double emaLng,
    required double prevLat,
    required double prevLng,
    required int currRPInd,
    required int nextRPInd,
    required int prevRPInd,
    required int currSegmInd,
    required int prevSegmInd,
    required double coveredDist,
    required double prevCoveredDist,
    required int initTicks,
    required int firstActiveSpInd,
    required int activeWpPtr,
    required bool isOnRoute,
    required bool isJump,
  })  : _route = route,
        _routeLen = routeLen,
        _distFromStart = distFromStart,
        _segmentsLen = segmentsLen,
        _srBuffer = srBuffer,
        _alignedSP = alignedSP,
        _spStates = spStates,
        _wpIndices = wpIndices,
        _emaLat = emaLat,
        _emaLng = emaLng,
        _prevLat = prevLat,
        _prevLng = prevLng,
        _currRPInd = currRPInd,
        _nextRPInd = nextRPInd,
        _prevRPInd = prevRPInd,
        _currSegmInd = currSegmInd,
        _prevSegmInd = prevSegmInd,
        _coveredDist = coveredDist,
        _prevCoveredDist = prevCoveredDist,
        _initTicks = initTicks,
        _firstActiveSpInd = firstActiveSpInd,
        _activeWpPtr = activeWpPtr,
        _isOnRoute = isOnRoute,
        _isJump = isJump;

  /// Reconstructs the engine from a pair of binary dump files previously
  /// created by [initFiles]. Reads both the immutable core data and the
  /// mutable navigation state.
  static Future<RouteDataEngine> fromFiles({
    required String corePath,
    required String statePath,
  }) {
    return _Serializer.loadFromFiles(corePath: corePath, statePath: statePath);
  }

  /// Writes the initial binary dumps to disk: immutable route data to
  /// [corePath], mutable navigation state to [statePath]. Intended to be
  /// called once after construction. To persist subsequent state changes,
  /// pass [statePath] to [updateState].
  Future<void> initFiles({
    required String corePath,
    required String statePath,
  }) async {
    await File(corePath).writeAsBytes(_Serializer.snapshotImmutable(this));
    await File(statePath).writeAsBytes(_Serializer.snapshotMutable(this));
  }

  /// Приватный хелпер для безопасного клонирования массива с 8-байтным выравниванием.
  /// Создает копию байтов, сохраняя 8-байтное аппаратное выравнивание памяти.
  SidePointStates _cloneAlignedU8() {
    // Длина _spStates уже кратна 8, просто делим.
    final int doublesCount = _spStates.length ~/ 8;

    // КРИТИЧНО: Аллоцируем именно через Float64List.
    // Если выделить память через Uint8List(_spStates.length), Dart может положить
    // её по невыровненному адресу в RAM. Тогда на ARM-архитектурах (Android/iOS)
    // при попытке прочитать это как Float64List приложение крашнется.
    final Float64List alignedCopy = Float64List(doublesCount);
    final Uint8List byteView = Uint8List.view(alignedCopy.buffer)
      ..setRange(0, _spStates.length, _spStates.buffer);

    return SidePointStates(byteView);
  }

  /// Exports a deep copy of all engine data as an [RMConfig] for use by
  /// [RouteManager]. The returned config is fully independent — mutating it
  /// (or the manager that consumes it) will not affect this engine's state.
  RMConfig createConfig() {
    if (_route.isEmpty) throw StateError('Engine is not initialized.');

    return RMConfig(
      // Энджин защищает свою память, отдавая наружу только копии
      route: Float64List.fromList(_route),
      distFromStart: Float64List.fromList(_distFromStart),
      segmentsLen: Float64List.fromList(_segmentsLen),
      srBuffer: SearchRectBuffer(Float64List.fromList(_srBuffer.buffer)),
      alignedSP: RawSidePointsBuffer(Float64List.fromList(_alignedSP.buffer)),
      wpIndices: Int64List.fromList(_wpIndices),
      spStates: _cloneAlignedU8(),
      routeLen: _routeLen,
      progress: RouteProgress(
        emaLat: _emaLat,
        emaLng: _emaLng,
        prevLat: _prevLat,
        prevLng: _prevLng,
        currRPInd: _currRPInd,
        nextRPInd: _nextRPInd,
        prevRPInd: _prevRPInd,
        currSegmInd: _currSegmInd,
        prevSegmInd: _prevSegmInd,
        coveredDist: _coveredDist,
        prevCoveredDist: _prevCoveredDist,
        initTicks: _initTicks,
        firstActiveSpInd: _firstActiveSpInd,
        activeWpPtr: _activeWpPtr,
        isOnRoute: _isOnRoute,
        isJump: _isJump,
      ),
    );
  }

  /// Returns a [Future] that completes when all pending disk writes have
  /// finished. Must be awaited before moving, renaming, or deleting the
  /// state file to avoid writing to a stale path.
  Future<void> flush() => _saveQueue.flush();

  /// Applies mutable state received from [RouteManager] (via
  /// [RouteManager.exportState]) back into the engine's fields.
  ///
  /// If [statePath] is provided, an atomic disk write is enqueued via the
  /// internal [_IoMutex]. Multiple rapid calls collapse into a
  /// single write of the most recent state — safe to call on every GPS tick.
  void updateState(RMState state, [String? statePath]) {
    _spStates = state.spStates;

    final progress = state.progress;
    _emaLat = progress.emaLat;
    _emaLng = progress.emaLng;
    _prevLat = progress.prevLat;
    _prevLng = progress.prevLng;
    _currRPInd = progress.currRPInd;
    _nextRPInd = progress.nextRPInd;
    _prevRPInd = progress.prevRPInd;
    _currSegmInd = progress.currSegmInd;
    _prevSegmInd = progress.prevSegmInd;
    _coveredDist = progress.coveredDist;
    _prevCoveredDist = progress.prevCoveredDist;
    _initTicks = progress.initTicks;
    _firstActiveSpInd = progress.firstActiveSpInd;
    _activeWpPtr = progress.activeWpPtr;
    _isOnRoute = progress.isOnRoute;
    _isJump = progress.isJump;

    if (statePath != null) {
      _saveQueue.enqueue(_Serializer.snapshotMutable(this), statePath);
    }
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

  final _IoMutex _saveQueue = _IoMutex();

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

  int _currRPInd = 0;
  int _nextRPInd = 1;
  int _prevRPInd = 0;
  int _currSegmInd = 0;
  int _prevSegmInd = 0;
  bool _isOnRoute = true;
  bool _isJump = false;

  double _emaLat;
  double _emaLng;
  double _prevLat;
  double _prevLng;

  double _coveredDist;
  double _prevCoveredDist;
  int _initTicks;
  int _firstActiveSpInd;
  int _activeWpPtr;
}
