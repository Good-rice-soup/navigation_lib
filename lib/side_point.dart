import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

enum PointSide { left, right }

enum PointState { past, next, onWay }

class SidePoint {
  SidePoint({
    required this.point,
    required this.routeInd,
    required this.side,
    required this.state,
    required this.dist,
  });

  final LatLng point;
  final int routeInd;
  final PointSide side;
  PointState state;
  double dist;

  SidePoint update({required PointState newState, required double newDist}) {
    state = newState;
    dist = newDist;
    return this;
  }

  SidePoint copy() {
    return SidePoint(
      point: point,
      routeInd: routeInd,
      side: side,
      state: state,
      dist: dist,
    );
  }
}
