import 'dart:isolate';
import 'dart:typed_data';

import 'search_rect.dart';
import 'side_point.dart';

// =============================================================================
// RouteProgress (Композиция примитивов)
// =============================================================================

/// Иммутабельный контейнер для всех скалярных значений и флагов маршрута.
class RouteProgress {
  const RouteProgress({
    required this.emaLat,
    required this.emaLng,
    required this.prevLat,
    required this.prevLng,
    required this.currRPInd,
    required this.nextRPInd,
    required this.prevRPInd,
    required this.currSegmInd,
    required this.prevSegmInd,
    required this.coveredDist,
    required this.prevCoveredDist,
    required this.initTicks,
    required this.firstActiveSpInd,
    required this.activeWpPtr,
    required this.isOnRoute,
    required this.isJump,
  });

  final double emaLat;
  final double emaLng;
  final double prevLat;
  final double prevLng;
  final int currRPInd;
  final int nextRPInd;
  final int prevRPInd;
  final int currSegmInd;
  final int prevSegmInd;
  final double coveredDist;
  final double prevCoveredDist;
  final int initTicks;
  final int firstActiveSpInd;
  final int activeWpPtr;
  final bool isOnRoute;
  final bool isJump;
}

// =============================================================================
// RMState (Мутабельное состояние)
// =============================================================================

/// Dart 3 Record для быстрой передачи стейта через порты.
typedef TransferableRMState = ({
  TransferableTypedData spStatesT,
  RouteProgress progress,
});

class RMState {
  RMState({
    required this.spStates,
    required this.progress,
  });

  factory RMState.fromTransferable(TransferableRMState t) {
    return RMState(
      spStates: SidePointStates(t.spStatesT.materialize().asUint8List()),
      progress: t.progress,
    );
  }

  final SidePointStates spStates;
  final RouteProgress progress;

  TransferableRMState toTransferable() {
    return (
      spStatesT: TransferableTypedData.fromList([spStates.buffer]),
      progress: progress,
    );
  }
}

// =============================================================================
// RMConfig (Стартовая конфигурация)
// =============================================================================

/// Dart 3 Record для быстрой передачи конфига через порты.
typedef TransferableRMConfig = ({
  TransferableTypedData routeT,
  TransferableTypedData distFromStartT,
  TransferableTypedData segmentsLenT,
  TransferableTypedData srBufferT,
  TransferableTypedData alignedSPT,
  TransferableTypedData wpIndicesT,
  TransferableTypedData spStatesT,
  double routeLen,
  RouteProgress progress,
});

class RMConfig {
  RMConfig({
    required this.route,
    required this.distFromStart,
    required this.segmentsLen,
    required this.srBuffer,
    required this.alignedSP,
    required this.wpIndices,
    required this.spStates,
    required this.routeLen,
    required this.progress,
  });

  factory RMConfig.fromTransferable(TransferableRMConfig t) {
    return RMConfig(
      route: t.routeT.materialize().asFloat64List(),
      distFromStart: t.distFromStartT.materialize().asFloat64List(),
      segmentsLen: t.segmentsLenT.materialize().asFloat64List(),
      srBuffer: SearchRectBuffer(t.srBufferT.materialize().asFloat64List()),
      alignedSP:
          RawSidePointsBuffer(t.alignedSPT.materialize().asFloat64List()),
      wpIndices: t.wpIndicesT.materialize().asInt64List(),
      spStates: SidePointStates(t.spStatesT.materialize().asUint8List()),
      routeLen: t.routeLen,
      progress: t.progress,
    );
  }

  final Float64List route;
  final Float64List distFromStart;
  final Float64List segmentsLen;
  final SearchRectBuffer srBuffer;
  final RawSidePointsBuffer alignedSP;
  final Int64List wpIndices;
  final SidePointStates spStates;
  final double routeLen;
  final RouteProgress progress;

  TransferableRMConfig toTransferable() {
    return (
      routeT: TransferableTypedData.fromList([route]),
      distFromStartT: TransferableTypedData.fromList([distFromStart]),
      segmentsLenT: TransferableTypedData.fromList([segmentsLen]),
      srBufferT: TransferableTypedData.fromList([srBuffer.buffer]),
      alignedSPT: TransferableTypedData.fromList([alignedSP.buffer]),
      wpIndicesT: TransferableTypedData.fromList([wpIndices]),
      spStatesT: TransferableTypedData.fromList([spStates.buffer]),
      routeLen: routeLen,
      progress: progress,
    );
  }
}
