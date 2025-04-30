enum PointPosition { left, right }

enum PointState { past, next, onWay }

class SidePoint {
  SidePoint({
    required this.routePointInd,
    required this.position,
    required this.state,
    required this.dist,
  });

  final int routePointInd;
  final PointPosition position;
  PointState state;
  double dist;

  SidePoint update({required PointState newState, required double newDist}) {
    state = newState;
    dist = newDist;
    return this;
  }

  SidePoint copy() {
    return SidePoint(
      routePointInd: routePointInd,
      position: position,
      state: state,
      dist: dist,
    );
  }
}
