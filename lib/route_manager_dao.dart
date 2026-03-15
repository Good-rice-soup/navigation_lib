import 'dart:math';
import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'geo_utils.dart';
import 'new_search_rect.dart';
import 'polyline_util.dart';
import 'side_point.dart';

/// Route manager data access object
class RouteManagerDAO {
  // ===========================================================================
  // 1. КОНСТРУКТОРЫ (ПУБЛИЧНЫЕ ТОЧКИ ВХОДА)
  // ===========================================================================

  /// Основной ООП-конструктор.
  /// Принимает объекты LatLng, переводит их в DOD-формат и запускает вычисления.
  factory RouteManagerDAO({
    required List<LatLng> route,
    required List<LatLng> sidePoints,
    required List<LatLng> wayPoints,
    double searchRectWidth = 10,
    double searchRectExtension = 5,
    double maxDistanceToSidePoint = 100.0,
    int ignoreSimplificationIfLess = 300,
  }) {
    // Конвертация объектов в примитивы
    final Float64List rawRoute = _checkForDuplications(route);
    final Float64List rawSP = _latLngListToFlat(sidePoints);
    final Float64List rawWP = _latLngListToFlat(wayPoints);

    return _build(
      route: rawRoute,
      sp: rawSP,
      wp: rawWP,
      srWidth: searchRectWidth,
      srExt: searchRectExtension,
      maxDst: maxDistanceToSidePoint,
      skipSimplify: ignoreSimplificationIfLess,
    );
  }

  /// Приватный конструктор-хранилище.
  RouteManagerDAO._({
    required Float64List route,
    required double routeLen,
    required Float64List distFromStart,
    required Float64List segmentsLen,
    required SearchRectBuffer srBuffer,
    required RawSidePointsBuffer alignedSP,
    required List<int> wpIndices,
    required int nextWPInd,
  })  : _route = route,
        _routeLen = routeLen,
        _distFromStart = distFromStart,
        _segmentsLen = segmentsLen,
        _srBuffer = srBuffer,
        _alignedSP = alignedSP,
        _wpIndices = wpIndices,
        _nextWPIndex = nextWPInd;

  /// DOD-конструктор для работы с изолятами.
  /// Принимает готовые массивы примитивов, считая их валидными.
  factory RouteManagerDAO.fromRawData({
    required Float64List route,
    required Float64List sidePoints,
    required Float64List wayPoints,
    double searchRectWidth = 10,
    double searchRectExtension = 5,
    double maxDistanceToSidePoint = 100.0,
    int ignoreSimplificationIfLess = 300,
  }) {
    return _build(
      route: route,
      sp: sidePoints,
      wp: wayPoints,
      srWidth: searchRectWidth,
      srExt: searchRectExtension,
      maxDst: maxDistanceToSidePoint,
      skipSimplify: ignoreSimplificationIfLess,
    );
  }

  /// Асинхронный конструктор для чтения файлов SoA.
  /// Набросок: читает байты и напрямую инициализирует хранилище.
  static Future<RouteManagerDAO> fromFile(String filePath) async {
    // TODO: Подключить модули записи и чтения SoA.
    // final bytes = await File(filePath).readAsBytes();
    // Парсинг байтов...

    return RouteManagerDAO._(
      route: Float64List(0),
      routeLen: 0.0,
      distFromStart: Float64List(0),
      segmentsLen: Float64List(0),
      srBuffer: SearchRectBuffer.allocate(0),
      alignedSP: RawSidePointsBuffer.empty(),
      wpIndices: [],
      nextWPInd: -1,
    );
  }

  // ===========================================================================
  // 2. ВЫЧИСЛИТЕЛЬНОЕ ЯДРО И ПРИВАТНОЕ ХРАНИЛИЩЕ
  // ===========================================================================

  /// Единый движок расчетов.
  /// Работает исключительно с примитивами и возвращает готовый инстанс DAO.
  static RouteManagerDAO _build({
    required Float64List route,
    required Float64List sp,
    required Float64List wp,
    required double srWidth,
    required double srExt,
    required double maxDst,
    required int skipSimplify,
  }) {
    if (route.length < 4) throw ArgumentError('Your route length less than 2');

    final int pointsAmount = route.length ~/ 2;
    final int segmentsAmount = pointsAmount - 1;

    final Float64List distFromStart = Float64List(pointsAmount);
    final Float64List segmentsLen = Float64List(segmentsAmount);
    final SearchRectBuffer srBuffer = SearchRectBuffer.allocate(segmentsAmount);

    double routeLen = 0;
    int pInd = 0;
    final int maxOffset = route.length - 2;

    // Расчет длины и буфера поиска
    for (int offset = 0; offset < maxOffset; offset += 2) {
      final double lat1 = route[offset];
      final double lon1 = route[offset + 1];
      final double lat2 = route[offset + 2];
      final double lon2 = route[offset + 3];

      final double dist = getDistanceRaw(lat1, lon1, lat2, lon2);
      distFromStart[pInd] = routeLen;
      segmentsLen[pInd] = dist;
      routeLen += dist;

      srBuffer.calculateAndSet(pInd, lat1, lon1, lat2, lon2, srWidth, srExt);
      pInd++;
    }
    distFromStart[pInd] = routeLen;

    final RawSidePointsBuffer alignedSP = RawSidePointsBuffer.empty();
    List<int> wpIndices = [];
    int nextWPInd = -1;

    if (sp.isNotEmpty || wp.isNotEmpty) {
      final res =
          rdpRouteSimplifierRaw(route, maxDst / 2, ignoreIfLess: skipSimplify);

      final Float64List simpRoute = res.route;
      final Uint32List mapping = res.mapping;

      final int simpSeg = (simpRoute.length ~/ 2) - 1;
      final SearchRectBuffer simpSR = SearchRectBuffer.allocate(simpSeg);
      final double searchFactor = maxDst * 1.5;

      for (int i = 0; i < simpSeg; i++) {
        final int offset = i * 2;
        simpSR.calculateAndSet(
          i,
          simpRoute[offset],
          simpRoute[offset + 1],
          simpRoute[offset + 2],
          simpRoute[offset + 3],
          searchFactor,
          searchFactor,
        );
      }

      _filtering(route, wp, sp, simpSR, simpSeg, mapping, maxDst, alignedSP);
      alignedSP.align();
      final mapResult = _mapping(route, distFromStart, alignedSP, wp);
      wpIndices = mapResult.wpIndices;
      nextWPInd = mapResult.nextWPIndex;
    }

    return RouteManagerDAO._(
      route: route,
      routeLen: routeLen,
      distFromStart: distFromStart,
      segmentsLen: segmentsLen,
      srBuffer: srBuffer,
      alignedSP: alignedSP,
      wpIndices: wpIndices,
      nextWPInd: nextWPInd,
    );
  }

  // ===========================================================================
  // 3. ПОЛЯ И СТЕЙТЫ
  // ===========================================================================

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

  // Мутабельные стейты для работы на маршруте
  int _currRPInd = 0;
  int _nextRPInd = 1;
  int _prevRPInd = 0;
  int _currSegmInd = 0;
  int _prevSegmInd = 0;
  bool _isOnRoute = true;
  bool _isJump = false;

  // ===========================================================================
  // 4. СТАТИЧЕСКИЕ УТИЛИТЫ И ЛОГИКА
  // ===========================================================================

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

  /// Утилита для плоского представления List<LatLng>.
  static Float64List _latLngListToFlat(List<LatLng> points) {
    if (points.isEmpty) return Float64List(0);
    final flat = Float64List(points.length * 2);
    for (int i = 0; i < points.length; i++) {
      flat[i * 2] = points[i].latitude;
      flat[i * 2 + 1] = points[i].longitude;
    }
    return flat;
  }

  static void _filtering(
    Float64List route,
    Float64List rawWP,
    Float64List rawSP,
    SearchRectBuffer srBuffer,
    int srSegAmount,
    Uint32List mapping,
    double maxDstToSP,
    RawSidePointsBuffer passedSP,
  ) {
    final int routePointsCount = route.length ~/ 2;
    double minDistRadSq;
    double distRadSq;
    int bestInd;

    // Предарасчет констант для быстрого сравнения квадратов (в радианах)
    final double maxDstRad = maxDstToSP / earthRadiusInMeters;
    final double maxDstRadSq = maxDstRad * maxDstRad;

    // --- ОБРАБОТКА WAYPOINTS ---
    for (int p = 0; p < rawWP.length; p += 2) {
      final double wpLat = rawWP[p];
      final double wpLng = rawWP[p + 1];

      bool foundInAnySegment = false;
      minDistRadSq = double.infinity;
      bestInd = 0;

      for (int i = 0; i < srSegAmount; i++) {
        if (!srBuffer.isPointInRect(i, wpLat, wpLng)) continue;

        foundInAnySegment = true;
        final int start = mapping[i];
        final int end = mapping[i + 1];

        int offset = start * 2;
        for (int rpInd = start; rpInd <= end; rpInd++) {
          distRadSq =
              getDistanceRadSq(wpLat, wpLng, route[offset], route[offset + 1]);

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
          distRadSq =
              getDistanceRadSq(wpLat, wpLng, route[offset], route[offset + 1]);

          if (distRadSq < minDistRadSq) {
            minDistRadSq = distRadSq;
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
    for (int p = 0; p < rawSP.length; p += 2) {
      final double spLat = rawSP[p];
      final double spLng = rawSP[p + 1];

      minDistRadSq = double.infinity;
      bestInd = -1;

      for (int i = 0; i < srSegAmount; i++) {
        if (!srBuffer.isPointInRect(i, spLat, spLng)) continue;

        final int start = mapping[i];
        final int end = mapping[i + 1];

        int offset = start * 2;
        for (int rpInd = start; rpInd <= end; rpInd++) {
          distRadSq =
              getDistanceRadSq(spLat, spLng, route[offset], route[offset + 1]);

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

  static ({List<int> wpIndices, int nextWPIndex}) _mapping(
    Float64List route,
    Float64List distFromStart,
    RawSidePointsBuffer alignedSPData,
    Float64List rawWP,
  ) {
    bool firstNextFlag = true;
    final int secondToLastIndex = (route.length ~/ 2) - 2;

    final List<int> localWpIndices = [];
    int localNextWPIndex = -1;

    for (int i = 0; i < alignedSPData.length; i++) {
      final RawSidePoint sp = alignedSPData[i];
      final int ind = sp.routeInd;

      // 1. Вычисляем индексы соседних точек без аллокаций LatLng
      final int closestInd = min(ind, secondToLastIndex);
      final int nextInd = closestInd + 1;

      final int closestOffset = closestInd * 2;
      final int nextOffset = nextInd * 2;

      final double closestLat = route[closestOffset];
      final double closestLng = route[closestOffset + 1];

      final double nextLat = route[nextOffset];
      final double nextLng = route[nextOffset + 1];

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

      // Если _currRPInd всегда 0 при инициализации DAO, оставляем так:
      const int initialCurrRPInd = 0;
      if (ind <= initialCurrRPInd) {
        sp.state = PointState.past;
      } else if (firstNextFlag) {
        sp.state = PointState.next;
        firstNextFlag = false;
      } else {
        sp.state = PointState.onWay;
      }

      sp.dist = distFromStart[ind] + sp.dist;

      // Проверка на WayPoint по сырым координатам (прямое сравнение double)
      bool isWp = false;
      for (int j = 0; j < rawWP.length; j += 2) {
        if (rawWP[j] == sp.lat && rawWP[j + 1] == sp.lng) {
          isWp = true;
          break;
        }
      }

      if (isWp) {
        localWpIndices.add(i);
      }
    }

    final reversedIndices = localWpIndices.reversed.toList();
    if (reversedIndices.isNotEmpty) {
      localNextWPIndex = reversedIndices.last;
    }

    return (wpIndices: reversedIndices, nextWPIndex: localNextWPIndex);
  }
}
