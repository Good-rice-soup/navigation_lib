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
    required this.historySize,
  })  : wpIndices = Int64List(wp.length ~/ 2),
        distFromStart = Float64List(route.length ~/ 2),
        segmentsLen = Float64List((route.length ~/ 2) - 1),
        srBuffer = SearchRectBuffer.allocate((route.length ~/ 2) - 1) {
    if (route.length < 4) throw ArgumentError('Your route length less than 2');
    if (historySize < 2) throw ArgumentError('historySize must be at least 2');
  }

  final Float64List route;
  final Float64List sp;
  final Float64List wp;
  final double srWidth;
  final double srExt;
  final double maxDst;
  final int skipSimplify;
  final int historySize;

  final Float64List distFromStart;
  final Float64List segmentsLen;
  final SearchRectBuffer srBuffer;

  double routeLen = 0;
  final RawSidePointsBuffer alignedSP = RawSidePointsBuffer.empty();
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

  void _filtering(SearchRectBuffer simpSR, int simpSeg, Uint32List mapping) {
    final int routePointsCount = route.length ~/ 2;
    double minDistRadSq;
    double distRadSq;
    int bestInd;

    final double maxDstRad = maxDst / earthRadiusInMeters;
    final double maxDstRadSq = maxDstRad * maxDstRad;

    // --- ОБРАБОТКА WAYPOINTS ---
    for (int p = 0; p < wp.length; p += 2) {
      final double wpLat = wp[p];
      final double wpLng = wp[p + 1];

      bool foundInAnySegment = false;
      minDistRadSq = double.infinity;
      bestInd = 0;

      for (int i = 0; i < simpSeg; i++) {
        if (!simpSR.isPointInRect(i, wpLat, wpLng)) continue;

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

      final RawSidePoint wpPoint = RawSidePoint.addUnmapped(
        lat: wpLat,
        lng: wpLng,
        dist: earthRadiusInMeters * sqrt(minDistRadSq),
        routeInd: bestInd,
      )..isWayPoint = true;
      alignedSP.add(wpPoint);
    }

    // --- ОБРАБОТКА SIDEPOINTS ---
    for (int p = 0; p < sp.length; p += 2) {
      final double spLat = sp[p];
      final double spLng = sp[p + 1];

      minDistRadSq = double.infinity;
      bestInd = -1;

      for (int i = 0; i < simpSeg; i++) {
        if (!simpSR.isPointInRect(i, spLat, spLng)) continue;

        final int start = mapping[i];
        final int end = mapping[i + 1];

        int offset = start * 2;
        for (int rpInd = start; rpInd <= end; rpInd++) {
          distRadSq =
              getDistanceRadSq(spLat, spLng, route[offset], route[offset + 1]);

          if (distRadSq <= maxDstRadSq && distRadSq < minDistRadSq) {
            minDistRadSq = distRadSq;
            bestInd = rpInd;
          }
          offset += 2;
        }
      }

      if (bestInd != -1) {
        alignedSP.add(RawSidePoint.addUnmapped(
          lat: spLat,
          lng: spLng,
          dist: earthRadiusInMeters * sqrt(minDistRadSq),
          routeInd: bestInd,
        ));
      }
    }
  }

  void _mapping() {
    bool firstNextFlag = true;
    final int secondToLastIndex = (route.length ~/ 2) - 2;
    int wpInsertPtr = wpIndices.length - 1;

    for (int i = 0; i < alignedSP.length; i++) {
      final RawSidePoint point = alignedSP[i];
      final int ind = point.routeInd;

      final int closestInd = min(ind, secondToLastIndex);
      final int nextInd = closestInd + 1;

      final int closest = closestInd * 2;
      final int next = nextInd * 2;

      final double closestLat = route[closest];
      final double closestLng = route[closest + 1];
      final double nextLat = route[next];
      final double nextLng = route[next + 1];

      final double skew = skewProductionRaw(
        closestLat,
        closestLng,
        nextLat,
        nextLng,
        point.lat,
        point.lng,
      );

      if (skew <= 0) {
        point.position = PointPosition.right;
      } else {
        point.position = PointPosition.left;
      }

      const int initialCurrRPInd = 0;
      if (ind <= initialCurrRPInd) {
        point.state = PointState.past;
      } else if (firstNextFlag) {
        point.state = PointState.next;
        firstNextFlag = false;
      } else {
        point.state = PointState.onWay;
      }

      point.dist = distFromStart[ind] + point.dist;

      // переворачиваем для более простого удаления пройденного
      if (point.isWayPoint) wpIndices[wpInsertPtr--] = i;
    }

    if (wpIndices.isNotEmpty) nextWPInd = wpIndices.last;
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

    _filtering(simpSR, simpSeg, mapping);
    alignedSP.align();
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
      wpIndices: wpIndices,
      nextWPInd: nextWPInd,
      historySize: historySize,
    );
  }
}
