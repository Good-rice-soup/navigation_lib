import 'package:flutter/cupertino.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

class RouteSimplificationConfig {
  RouteSimplificationConfig({required this.config});
  late final Set<ZoomToFactor> config;
}

@immutable
class ZoomToFactor {
  const ZoomToFactor(
      {this.isUseOriginalRouteInVisibleArea = false,
        this.boundsExpansionFactor = 1,
        required this.zoom,
        required this.routeSimplificationFactor});

  final double zoom;
  final double routeSimplificationFactor;
  final double boundsExpansionFactor;
  final bool isUseOriginalRouteInVisibleArea;
}

@immutable
class RoutePaintHelper {
  const RoutePaintHelper({required this.config, required this.route});

  final List<LatLng> route;

  final RouteSimplificationConfig config;

  List<LatLng> getRoute(
      {required LatLngBounds bounds,
        required double zoom,
        required LatLng currentLocation}) {
    return [];
  }
}

void main(){
  RoutePaintHelper(
    config: RouteSimplificationConfig(
      config: {
        const ZoomToFactor(
          zoom: 10,
          routeSimplificationFactor: 0.5,
          boundsExpansionFactor: 1.5,
        ),
        const ZoomToFactor(
          zoom: 15,
          routeSimplificationFactor: 0.1,
          boundsExpansionFactor: 1.1,
        ),
      },
    ),
    route: const [
      LatLng(0, 0),
      LatLng(1, 1),
      LatLng(2, 2),
    ],
  ).getRoute(
    bounds: LatLngBounds(
      southwest: const LatLng(0, 0),
      northeast: const LatLng(1, 1),
    ),
    zoom: 10,
    currentLocation: const LatLng(0, 0),
  );
}