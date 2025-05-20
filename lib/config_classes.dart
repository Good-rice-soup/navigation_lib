import 'dart:collection';

class ZoomConfig {
  const ZoomConfig({
    required this.zoomLevel,
    this.simplificationTolerance = 0.0,
    this.boundsExpansion = 1.0,
    this.useOriginalRouteInView = false,
  });

  final int zoomLevel;
  final double simplificationTolerance;
  final double boundsExpansion;
  final bool useOriginalRouteInView;
}

class RouteSimplificationConfig {
  RouteSimplificationConfig(Iterable<ZoomConfig> configs)
      : _configs = UnmodifiableMapView(_validateConfigs(configs));

  final UnmodifiableMapView<int, ZoomConfig> _configs;

  static Map<int, ZoomConfig> _validateConfigs(Iterable<ZoomConfig> configs) {
    final Map<int, ZoomConfig> map = {};
    for (final ZoomConfig config in configs) {
      assert(!map.containsKey(config.zoomLevel),
          'Duplicate zoom level ${config.zoomLevel}');
      map[config.zoomLevel] = config;
    }
    return map;
  }

  ZoomConfig getConfig(int zoom) {
    if (_configs.containsKey(zoom)) {
      return _configs[zoom]!;
    }
    throw StateError(
      'Config for zoom $zoom not found. Available zooms: ${_configs.keys.join(', ')}',
    );
  }

  UnmodifiableMapView<int, ZoomConfig> get zoomConfigs => _configs;
}
