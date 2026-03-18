part of 'engine.dart';

extension _Serializer on RouteDataEngine {
  @pragma('vm:prefer-inline')
  static int _writeList(
    Float64List target,
    Int64List targetIntView,
    int offset,
    Float64List source,
  ) {
    targetIntView[offset] = source.length;
    target.setAll(offset + 1, source);
    return offset + 1 + source.length;
  }

  static Future<void> saveImmutable(RouteDataEngine engine, String path) async {
    int totalDoubles = 2;
    totalDoubles += 1 + engine._route.length;
    totalDoubles += 1 + engine._distFromStart.length;
    totalDoubles += 1 + engine._segmentsLen.length;
    totalDoubles += 1 + engine._srBuffer.buffer.length;

    final flat = Float64List(totalDoubles);
    final intView = flat.buffer.asInt64List();
    int ptr = 0;

    flat[ptr++] = engine._routeLen;
    intView[ptr++] = engine._historySize;

    ptr = _writeList(flat, intView, ptr, engine._route);
    ptr = _writeList(flat, intView, ptr, engine._distFromStart);
    ptr = _writeList(flat, intView, ptr, engine._segmentsLen);
    ptr = _writeList(flat, intView, ptr, engine._srBuffer.buffer);

    await File(path).writeAsBytes(flat.buffer.asUint8List());
  }

  static Future<void> saveMutable(RouteDataEngine engine, String path) async {
    final Float64List spFlat = engine._alignedSP.toFlatBuffer();

    int totalDoubles = 8;
    totalDoubles += 1 + spFlat.length;
    totalDoubles += 1 + engine._wpIndices.length;

    final flat = Float64List(totalDoubles);
    final intView = flat.buffer.asInt64List();
    int ptr = 0;

    intView[ptr++] = engine._currRPInd;
    intView[ptr++] = engine._nextRPInd;
    intView[ptr++] = engine._prevRPInd;
    intView[ptr++] = engine._currSegmInd;
    intView[ptr++] = engine._prevSegmInd;
    intView[ptr++] = engine._nextWPIndex;
    intView[ptr++] = engine._isOnRoute ? 1 : 0;
    intView[ptr++] = engine._isJump ? 1 : 0;

    ptr = _writeList(flat, intView, ptr, spFlat);

    intView[ptr++] = engine._wpIndices.length;
    intView.setAll(ptr, engine._wpIndices);
    ptr += engine._wpIndices.length;

    await File(path).writeAsBytes(flat.buffer.asUint8List());
  }

  @pragma('vm:prefer-inline')
  static Float64List _readList(
    Float64List source,
    Int64List sourceIntView,
    int offset,
  ) {
    final length = sourceIntView[offset];
    return Float64List.sublistView(source, offset + 1, offset + 1 + length);
  }

  static Future<RouteDataEngine> loadFromFiles({
    required String corePath,
    required String statePath,
  }) async {
    // --- ИММУТАБЕЛЬНАЯ ЧАСТЬ ---
    final immBytes = await File(corePath).readAsBytes();
    final immFlat = immBytes.buffer.asFloat64List();
    final immIntView = immBytes.buffer.asInt64List();
    int immPtr = 0;

    final routeLen = immFlat[immPtr++];
    final historySize = immIntView[immPtr++];

    final routeView = _readList(immFlat, immIntView, immPtr);
    immPtr += 1 + routeView.length;

    final distView = _readList(immFlat, immIntView, immPtr);
    immPtr += 1 + distView.length;

    final segView = _readList(immFlat, immIntView, immPtr);
    immPtr += 1 + segView.length;

    final srView = _readList(immFlat, immIntView, immPtr);
    immPtr += 1 + srView.length;
    final srBuffer = SearchRectBuffer.fromBytes(srView);

    // --- МУТАБЕЛЬНАЯ ЧАСТЬ ---
    final mutBytes = await File(statePath).readAsBytes();
    final mutFlat = mutBytes.buffer.asFloat64List();
    final mutIntView = mutBytes.buffer.asInt64List();
    int mutPtr = 0;

    final currRPInd = mutIntView[mutPtr++];
    final nextRPInd = mutIntView[mutPtr++];
    final prevRPInd = mutIntView[mutPtr++];
    final currSegmInd = mutIntView[mutPtr++];
    final prevSegmInd = mutIntView[mutPtr++];
    final nextWPIndex = mutIntView[mutPtr++];
    final isOnRoute = mutIntView[mutPtr++] == 1;
    final isJump = mutIntView[mutPtr++] == 1;

    final spView = _readList(mutFlat, mutIntView, mutPtr);
    mutPtr += 1 + spView.length;
    final alignedSP = RawSidePointsBuffer.fromFlatBuffer(spView);

    final wpLength = mutIntView[mutPtr++];
    final Int64List wpIndices =
        Int64List.view(mutBytes.buffer, mutPtr * 8, wpLength);
    mutPtr += wpLength;

    return RouteDataEngine._(
      route: routeView,
      routeLen: routeLen,
      distFromStart: distView,
      segmentsLen: segView,
      srBuffer: srBuffer,
      alignedSP: alignedSP,
      wpIndices: wpIndices,
      nextWPInd: nextWPIndex,
      historySize: historySize,
    )
      .._currRPInd = currRPInd
      .._nextRPInd = nextRPInd
      .._prevRPInd = prevRPInd
      .._currSegmInd = currSegmInd
      .._prevSegmInd = prevSegmInd
      .._isOnRoute = isOnRoute
      .._isJump = isJump;
  }
}
