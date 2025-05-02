import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'search_rect.dart';
import 'side_point.dart';

class CopyPolicy {
  CopyPolicy({
    this.deepCopyRoute = true,
    this.deepCopySearchRects = true,
    this.deepCopySidePoints = true,
  });

  final bool deepCopyRoute;
  final bool deepCopySidePoints;
  final bool deepCopySearchRects;

  List<LatLng> route(List<LatLng> orig) => deepCopyRoute
      ? [for (final p in orig) LatLng(p.latitude, p.longitude)]
      : orig;

  Map<int, SidePoint> sidePoints(Map<int, SidePoint> orig) => deepCopySidePoints
      ? {for (final e in orig.entries) e.key: e.value.copy()}
      : orig;

  Map<int, SearchRect> searchRect(Map<int, SearchRect> orig) =>
      deepCopySearchRects
          ? {
              for (final e in orig.entries)
                e.key: SearchRect.copy(
                  rect: e.value.rect,
                  segmentVector: e.value.segmentVector,
                )
            }
          : orig;
}
