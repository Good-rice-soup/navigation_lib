enum RelativePosition { left, right }

enum PointStatus { past, next, onWay }

class SidePoint {
  SidePoint({
    required int alignedInd,
    required int closestRoutePointInd,
    required RelativePosition position,
    required PointStatus status,
    required double dist,
  }) {
    _alignedInd = alignedInd;
    _closestRoutePointInd = closestRoutePointInd;
    _position = position;
    _status = status;
    _dist = dist;
  }

  late final int _alignedInd;
  late final int _closestRoutePointInd;
  late final RelativePosition _position;
  late PointStatus _status;
  late double _dist;

  void update({
    required PointStatus newStatus,
    required double newDistance,
  }) {
    _status = newStatus;
    _dist = newDistance;
  }

  int get alignedInd => _alignedInd;

  int get closestRoutePointInd => _closestRoutePointInd;

  RelativePosition get position => _position;

  PointStatus get status => _status;

  double get dist => _dist;
}
