import 'dart:typed_data';

import 'new_search_rect.dart';
import 'side_point.dart';

/// Неизменяемая стартовая конфигурация для инициализации RouteManager.
/// Передается из DAO в момент создания менеджера.
class RMConfig {
  RMConfig({
    required this.route,
    required this.distFromStart,
    required this.segmentsLen,
    required this.srBuffer,
    required this.alignedSP,
    required this.wpIndices,
    required this.routeLen,
    required this.historySize,
  });

  // Массивы передаются по ссылке (zero-copy)
  final Float64List route;
  final Float64List distFromStart;
  final Float64List segmentsLen;
  final SearchRectBuffer srBuffer;
  final RawSidePointsBuffer alignedSP;
  final Int64List wpIndices;

  final double routeLen;
  final int historySize;
}

/// Мутабельное состояние маршрута.
/// Генерируется менеджером и передается в DAO для сохранения на диск.
class RMState {
  RMState({
    required this.currRPInd,
    required this.nextRPInd,
    required this.prevRPInd,
    required this.currSegmInd,
    required this.prevSegmInd,
    required this.nextWPIndex,
    required this.isOnRoute,
    required this.isJump,
    // Если менеджер мутирует сами буферы напрямую, передавать их здесь не обязательно,
    // но если нужно отслеживать добавление новых точек, можно добавить:
    // required this.alignedSP,
  });

  final int currRPInd;
  final int nextRPInd;
  final int prevRPInd;
  final int currSegmInd;
  final int prevSegmInd;
  final int nextWPIndex;

  final bool isOnRoute;
  final bool isJump;
}
