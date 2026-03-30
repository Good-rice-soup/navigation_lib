part of 'engine.dart';

extension _Serializer on RouteDataEngine {
  static Future<void> saveImmutable(RouteDataEngine engine, String path) async {
    int totalDoubles = 1; // 1 слот под routeLen
    totalDoubles += 1 + engine._route.length;
    totalDoubles += 1 + engine._distFromStart.length;
    totalDoubles += 1 + engine._segmentsLen.length;
    totalDoubles += 1 + engine._srBuffer.lengthIn64Bits;
    totalDoubles += 1 + engine._alignedSP.lengthIn64Bits;
    totalDoubles += 1 + engine._wpIndices.length;

    final writer = BinaryWriter(totalDoubles)
      ..writeDouble(engine._routeLen)
      ..writeDoubleList(engine._route)
      ..writeDoubleList(engine._distFromStart)
      ..writeDoubleList(engine._segmentsLen)
      ..writeDoubleList(engine._srBuffer.buffer)
      ..writeDoubleList(engine._alignedSP.buffer)
      ..writeIntList(engine._wpIndices);

    await File(path).writeAsBytes(writer.toBytes());
  }

  static Future<void> saveMutable(RouteDataEngine engine, String path) async {
    // 6 doubles + 10 ints = 16 слотов
    int totalDoubles = 16;
    totalDoubles += 1 + engine._spStates.lengthIn64Bits;

    final writer = BinaryWriter(totalDoubles)
      ..writeDouble(engine._emaLat)
      ..writeDouble(engine._emaLng)
      ..writeDouble(engine._prevLat)
      ..writeDouble(engine._prevLng)
      ..writeDouble(engine._coveredDist)
      ..writeDouble(engine._prevCoveredDist)
      ..writeInt(engine._currRPInd)
      ..writeInt(engine._nextRPInd)
      ..writeInt(engine._prevRPInd)
      ..writeInt(engine._currSegmInd)
      ..writeInt(engine._prevSegmInd)
      ..writeInt(engine._initTicks)
      ..writeInt(engine._firstActiveSpInd)
      ..writeInt(engine._activeWpPtr)
      ..writeBool(engine._isOnRoute)
      ..writeBool(engine._isJump)
      ..writeAlignedBytes(
          engine._spStates.buffer, engine._spStates.lengthIn64Bits);

    await File(path).writeAsBytes(writer.toBytes());
  }

  static Future<RouteDataEngine> loadFromFiles({
    required String corePath,
    required String statePath,
  }) async {
    // --- ИММУТАБЕЛЬНАЯ ЧАСТЬ ---
    final immBytes = await File(corePath).readAsBytes();
    final immReader = BinaryReader(immBytes);

    final routeLen = immReader.readDouble();
    final routeView = immReader.readDoubleList();
    final distView = immReader.readDoubleList();
    final segView = immReader.readDoubleList();
    final srBuffer = SearchRectBuffer(immReader.readDoubleList());
    final alignedSP = RawSidePointsBuffer(immReader.readDoubleList());
    final wpIndicesView = immReader.readIntList();

    // --- МУТАБЕЛЬНАЯ ЧАСТЬ ---
    final mutBytes = await File(statePath).readAsBytes();
    final mutReader = BinaryReader(mutBytes);

    final emaLat = mutReader.readDouble();
    final emaLng = mutReader.readDouble();
    final prevLat = mutReader.readDouble();
    final prevLng = mutReader.readDouble();
    final coveredDist = mutReader.readDouble();
    final prevCoveredDist = mutReader.readDouble();

    final currRPInd = mutReader.readInt();
    final nextRPInd = mutReader.readInt();
    final prevRPInd = mutReader.readInt();
    final currSegmInd = mutReader.readInt();
    final prevSegmInd = mutReader.readInt();
    final initTicks = mutReader.readInt();
    final firstActiveSpInd = mutReader.readInt();
    final activeWpPtr = mutReader.readInt();
    final isOnRoute = mutReader.readBool();
    final isJump = mutReader.readBool();

    final spStates = SidePointStates(mutReader.readAlignedBytes());

    return RouteDataEngine._(
      route: routeView,
      routeLen: routeLen,
      distFromStart: distView,
      segmentsLen: segView,
      srBuffer: srBuffer,
      alignedSP: alignedSP,
      wpIndices: wpIndicesView,
      spStates: spStates,
      emaLat: emaLat,
      emaLng: emaLng,
      prevLat: prevLat,
      prevLng: prevLng,
      currRPInd: currRPInd,
      nextRPInd: nextRPInd,
      prevRPInd: prevRPInd,
      currSegmInd: currSegmInd,
      prevSegmInd: prevSegmInd,
      coveredDist: coveredDist,
      prevCoveredDist: prevCoveredDist,
      initTicks: initTicks,
      firstActiveSpInd: firstActiveSpInd,
      activeWpPtr: activeWpPtr,
      isOnRoute: isOnRoute,
      isJump: isJump,
    );
  }
}
