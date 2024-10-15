class ZoomToFactor {
  const ZoomToFactor({
    this.isUseOriginalRouteInVisibleArea = false,
    this.boundsExpansionFactor = 1,
    required this.zoom,
    required this.routeSimplificationFactor,
  });

  final int zoom;
  final double routeSimplificationFactor;
  final double boundsExpansionFactor;
  final bool isUseOriginalRouteInVisibleArea;
}

class RouteSimplificationConfig {
  RouteSimplificationConfig({required this.config});

  final Set<ZoomToFactor> config;

  ZoomToFactor getConfigForZoom(int zoom) {
    return config.firstWhere((zoomFactor) => zoomFactor.zoom == zoom);
  }
}
