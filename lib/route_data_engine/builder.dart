part of 'engine.dart';

class _Builder {
  _Builder({
    required this.route,
    required this.sp,
    required this.wp,
    required this.srWidth,
    required this.srExt,
    required this.maxDst,
    required this.skipSimplify,
  })  : _emaLat = route[0],
        _emaLng = route[1],
        _prevLat = route[0],
        _prevLng = route[1],
        wpIndices = Int64List(wp.length ~/ 2),
        distFromStart = Float64List(route.length ~/ 2),
        segmentsLen = Float64List((route.length ~/ 2) - 1),
        srBuffer = SearchRectBuffer.allocate((route.length ~/ 2) - 1),
        alignedSP = RawSidePointsBuffer(Float64List(0)),
        spStates = SidePointStates(Uint8List.view(Float64List(0).buffer)) {
    if (route.length < 4) throw ArgumentError('Your route length less than 2');
  }

  final Float64List route;
  final Float64List sp;
  final Float64List wp;
  final double srWidth;
  final double srExt;
  final double maxDst;
  final int skipSimplify;

  final Float64List distFromStart;
  final Float64List segmentsLen;
  final SearchRectBuffer srBuffer;

  final double _emaLat;
  final double _emaLng;
  final double _prevLat;
  final double _prevLng;

  double routeLen = 0;
  RawSidePointsBuffer alignedSP;
  SidePointStates spStates;
  Int64List wpIndices;
  int nextWPInd = -1;

  void initSearchRectsAndDistances() {
    int pInd = 0;
    final int maxOffset = route.length - 2;

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
  }

  ({int totalCount, int wpCount}) _filtering(
    SearchRectBuffer simpSR,
    int simpSeg,
    Uint32List mapping,
    Float64List wpDists,
  ) {
    final int routePointsAmount = route.length ~/ 2;
    int pointIndex = 0;
    int wpMapped = 0;
    double distRadSq;

    // --- ОБРАБОТКА WAYPOINTS ---
    for (int p = 0; p < wp.length; p += 2) {
      final double wpLat = wp[p];
      final double wpLng = wp[p + 1];

      bool foundInAnySegment = false;
      double minDistRadSq = double.infinity;

      int bestSegmInd = 0;
      double bestAbsDistMeters = 0.0;
      double bestT = 0.0;

      for (int i = 0; i < simpSeg; i++) {
        if (!simpSR.isPointInRect(i, wpLat, wpLng)) continue;

        foundInAnySegment = true;
        final int start = mapping[i];
        final int end = mapping[i + 1];

        int offset = start * 2;
        // Перебираем сегменты, поэтому строго < end
        for (int rpInd = start; rpInd < end; rpInd++) {
          final double aLat = route[offset];
          final double aLng = route[offset + 1];
          final double bLat = route[offset + 2];
          final double bLng = route[offset + 3];

          final proj = getProjectionRaw(wpLat, wpLng, aLat, aLng, bLat, bLng);
          distRadSq = getDistanceRadSq(wpLat, wpLng, proj.lat, proj.lng);

          if (distRadSq < minDistRadSq) {
            minDistRadSq = distRadSq;
            bestSegmInd = rpInd;
            bestT = proj.t;
            bestAbsDistMeters =
                distFromStart[rpInd] + (proj.t * segmentsLen[rpInd]);
          }
          offset += 2;
        }
      }

      if (!foundInAnySegment) {
        int offset = 0;
        // Перебираем все сегменты маршрута (count - 1)
        for (int rpInd = 0; rpInd < routePointsAmount - 1; rpInd++) {
          final double aLat = route[offset];
          final double aLng = route[offset + 1];
          final double bLat = route[offset + 2];
          final double bLng = route[offset + 3];

          final proj = getProjectionRaw(wpLat, wpLng, aLat, aLng, bLat, bLng);
          distRadSq = getDistanceRadSq(wpLat, wpLng, proj.lat, proj.lng);

          if (distRadSq < minDistRadSq) {
            minDistRadSq = distRadSq;
            bestSegmInd = rpInd;
            bestT = proj.t;
            bestAbsDistMeters =
                distFromStart[rpInd] + (proj.t * segmentsLen[rpInd]);
          }
          offset += 2;
        }
      }

      final int closestPointInd = bestT > 0.5 ? bestSegmInd + 1 : bestSegmInd;

      alignedSP.setSidePoint(
        pointIndex,
        lat: wpLat,
        lng: wpLng,
        absDist: bestAbsDistMeters,
        orthoOffset: earthRadiusInMeters * sqrt(minDistRadSq),
        routeInd: closestPointInd,
      );
      wpDists[wpMapped++] = bestAbsDistMeters;
      pointIndex++;
    }

    // --- ОБРАБОТКА SIDEPOINTS ---
    final double maxDstRad = maxDst / earthRadiusInMeters;
    final double maxDstRadSq = maxDstRad * maxDstRad;

    for (int p = 0; p < sp.length; p += 2) {
      final double spLat = sp[p];
      final double spLng = sp[p + 1];

      double minDistRadSq = double.infinity;

      int bestSegmInd = -1;
      double bestAbsDistMeters = 0.0;
      double bestT = 0.0;

      for (int i = 0; i < simpSeg; i++) {
        if (!simpSR.isPointInRect(i, spLat, spLng)) continue;

        final int start = mapping[i];
        final int end = mapping[i + 1];

        int offset = start * 2;
        for (int rpInd = start; rpInd < end; rpInd++) {
          final double aLat = route[offset];
          final double aLng = route[offset + 1];
          final double bLat = route[offset + 2];
          final double bLng = route[offset + 3];

          final proj = getProjectionRaw(spLat, spLng, aLat, aLng, bLat, bLng);
          distRadSq = getDistanceRadSq(spLat, spLng, proj.lat, proj.lng);

          if (distRadSq <= maxDstRadSq && distRadSq < minDistRadSq) {
            minDistRadSq = distRadSq;
            bestSegmInd = rpInd;
            bestT = proj.t;
            bestAbsDistMeters =
                distFromStart[rpInd] + (proj.t * segmentsLen[rpInd]);
          }
          offset += 2;
        }
      }

      if (bestSegmInd != -1) {
        final int closestPointInd = bestT > 0.5 ? bestSegmInd + 1 : bestSegmInd;

        alignedSP.setSidePoint(
          pointIndex,
          lat: spLat,
          lng: spLng,
          absDist: bestAbsDistMeters,
          orthoOffset: earthRadiusInMeters * sqrt(minDistRadSq),
          routeInd: closestPointInd,
        );
        pointIndex++;
      }
    }

    return (totalCount: pointIndex, wpCount: wpMapped);
  }

  void _restoreWayPointFlags(int wpCount, int totalCount, Float64List wpDists) {
    for (int i = 0; i < wpCount; i++) {
      final double targetDist = wpDists[i];
      int low = 0;
      int high = totalCount - 1;

      while (low <= high) {
        final int mid = (low + high) >> 1;
        final double midVal = alignedSP.getAbsDist(mid);

        if (midVal == targetDist) {
          wpIndices[i] = mid;
          break;
        }
        if (midVal < targetDist) {
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
    }
    // Гарантируем строгий порядок возрастания индексов для _mapping
    wpIndices.sort();
  }

  void _mapping() {
    bool firstNextFlag = true;
    final int secondToLastIndex = (route.length ~/ 2) - 2;
    int wpCheckPtr = 0;

    for (int i = 0; i < alignedSP.length; i++) {
      final int ind = alignedSP.getRouteInd(i);

      final int closestInd = min(ind, secondToLastIndex);
      final int nextInd = closestInd + 1;

      final int closest = closestInd * 2;
      final int next = nextInd * 2;

      final double skew = skewProductionRaw(
        route[closest],
        route[closest + 1],
        route[next],
        route[next + 1],
        alignedSP.getLat(i),
        alignedSP.getLng(i),
      );

      final PointPosition position;
      if (skew <= 0) {
        position = PointPosition.right;
      } else {
        position = PointPosition.left;
      }

      final PointState state;
      const int initialCurrRPInd = 0;
      if (ind <= initialCurrRPInd) {
        state = PointState.past;
      } else if (firstNextFlag) {
        state = PointState.next;
        firstNextFlag = false;
      } else {
        state = PointState.onWay;
      }

      bool isWayPoint = false;
      if (wpCheckPtr < wpIndices.length && i == wpIndices[wpCheckPtr]) {
        isWayPoint = true;
        wpCheckPtr++;
      }

      spStates.setAll(i, state, position, isWayPoint);
    }

    if (wpIndices.isNotEmpty) nextWPInd = wpIndices.first;
  }

  void filterAndMapSidePoints() {
    if (sp.isEmpty && wp.isEmpty) return;

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

    final int maxPossiblePoints = (wp.length ~/ 2) + (sp.length ~/ 2);
    final Float64List rawSpatial = Float64List(maxPossiblePoints * 5);
    final Float64List wpDists = Float64List(wp.length ~/ 2);

    alignedSP = RawSidePointsBuffer(rawSpatial);

    // 1. Собираем пространственные данные
    final counts = _filtering(simpSR, simpSeg, mapping, wpDists);

    // 2. Обрезаем пустой хвост через sublistView (zero-cost) и сортируем
    final Float64List actualSpatial =
        Float64List.sublistView(rawSpatial, 0, counts.totalCount * 5);
    alignedSP = RawSidePointsBuffer(actualSpatial).align();

    // 3. Выделяем выровненный по 8 байтам буфер стейтов (строго нулями)
    final int doublesCount = (counts.totalCount + 7) ~/ 8;
    spStates =
        SidePointStates(Uint8List.view(Float64List(doublesCount).buffer));

    // 4. Восстанавливаем индексы WayPoint бинарным поиском за O(W log N)
    _restoreWayPointFlags(counts.wpCount, counts.totalCount, wpDists);

    _mapping();
  }

  RouteDataEngine build() {
    return RouteDataEngine._(
      route: route,
      routeLen: routeLen,
      distFromStart: distFromStart,
      segmentsLen: segmentsLen,
      srBuffer: srBuffer,
      alignedSP: alignedSP,
      spStates: spStates,
      wpIndices: wpIndices,
      nextWPInd: nextWPInd,
      emaLat: _emaLat,
      emaLng: _emaLng,
      prevLat: _prevLat,
      prevLng: _prevLng,
    );
  }
}
