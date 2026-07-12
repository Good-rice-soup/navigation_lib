/// On-device GPS route navigation: tracks a device's progress along a predefined
/// route, manages side points, simplifies polylines per map zoom, and persists
/// route state (optionally across isolates).
///
/// Main entry points: RouteManager, RouteDataEngine, PolylineSimplifier.
library;

export 'src/config_classes.dart';
export 'src/geo_utils.dart';
export 'src/polyline_util.dart';
export 'src/polylines_simplifier.dart';
export 'src/route_data_engine/engine.dart';
export 'src/route_manager.dart';
export 'src/route_transfer_objects.dart';
export 'src/side_point.dart';
