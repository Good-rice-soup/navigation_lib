import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

@immutable
class NodeData {
  const NodeData(this.point, this.index);

  final LatLng point;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is NodeData && other.point == point && other.index == index;

  @override
  int get hashCode => Object.hash(point, index);

  @override
  String toString() {
    return 'NodeData($point, $index)';
  }
}

class QuadTree {
  QuadTree(this.bounds, [this.insertPrecision = 0.00001, this.depth = 0]) {
    final double midLat =
        (bounds.southwest.latitude + bounds.northeast.latitude) / 2;
    final double swLng = bounds.southwest.longitude;
    final double neLng = bounds.northeast.longitude;

    double midLng;
    if (swLng <= neLng) {
      midLng = (swLng + neLng) / 2;
    } else {
      final double swLngPart = 180 - swLng;
      final double neLngPart = neLng + 180;
      final double shift = (swLngPart + neLngPart) / 2;
      midLng = swLng + shift;
    }

    middlePoint = LatLng(midLat, midLng);
    topLeftBounds = LatLngBounds(
      southwest: LatLng(bounds.southwest.latitude, midLng),
      northeast: LatLng(midLat, bounds.northeast.longitude),
    );
    botLeftBounds =
        LatLngBounds(southwest: bounds.southwest, northeast: middlePoint);
    topRightBounds =
        LatLngBounds(southwest: middlePoint, northeast: bounds.northeast);
    botRightBounds = LatLngBounds(
      southwest: LatLng(midLat, bounds.southwest.longitude),
      northeast: LatLng(bounds.northeast.latitude, midLng),
    );
  }

  final int depth;
  final LatLngBounds bounds;
  final List<NodeData> _leaf = [];
  late final LatLng middlePoint;
  bool _hasChildren = false;
  final double insertPrecision;

  late final LatLngBounds topLeftBounds;
  late final LatLngBounds botLeftBounds;
  late final LatLngBounds topRightBounds;
  late final LatLngBounds botRightBounds;

  QuadTree? _topLeftTree;
  QuadTree? _botLeftTree;
  QuadTree? _topRightTree;
  QuadTree? _botRightTree;

  void insert(NodeData node) {
    if (!bounds.contains(node.point)) {
      throw ArgumentError('Inserted node out of region at depth $depth');
    }

    if (_hasChildren) {
      _insertIntoChild(node);
    } else if (_leaf.isNotEmpty) {
      final double diffLat = _leaf.first.point.latitude - node.point.latitude;
      final double diffLng = _leaf.first.point.longitude - node.point.longitude;

      if (diffLat.abs() < insertPrecision && diffLng.abs() < insertPrecision) {
        return _leaf.add(node);
      }

      _leaf
        ..forEach(_insertIntoChild)
        ..clear();
      _insertIntoChild(node);
      return;
    } else {
      _leaf.add(node);
    }
  }

  void _insertIntoChild(NodeData node) {
    final LatLng point = node.point;
    if (botLeftBounds.contains(point)) {
      _botLeftTree ??= QuadTree(botLeftBounds, insertPrecision, depth + 1);
      _botLeftTree!.insert(node);
    } else if (topLeftBounds.contains(point)) {
      _topLeftTree ??= QuadTree(topLeftBounds, insertPrecision, depth + 1);
      _topLeftTree!.insert(node);
    } else if (botRightBounds.contains(point)) {
      _botRightTree ??= QuadTree(botRightBounds, insertPrecision, depth + 1);
      _botRightTree!.insert(node);
    } else if (topRightBounds.contains(point)) {
      _topRightTree ??= QuadTree(topRightBounds, insertPrecision, depth + 1);
      _topRightTree!.insert(node);
    } else {
      throw ArgumentError('Impossible error: node out of region after checks');
    }
    _hasChildren = true;
  }

  List<NodeData> search(LatLng point) {
    if (!bounds.contains(point)) return [];
    if (!_hasChildren) return _leaf;

    if (botLeftBounds.contains(point) && _botLeftTree != null) {
      return _botLeftTree!.search(point);
    } else if (topLeftBounds.contains(point) && _topLeftTree != null) {
      return _topLeftTree!.search(point);
    } else if (botRightBounds.contains(point) && _botRightTree != null) {
      return _botRightTree!.search(point);
    } else if (topRightBounds.contains(point) && _topRightTree != null) {
      return _topRightTree!.search(point);
    } else {
      final List<NodeData> leafs = [];
      if (_botLeftTree != null) leafs.addAll(_getLeafs(_botLeftTree!));
      if (_topLeftTree != null) leafs.addAll(_getLeafs(_topLeftTree!));
      if (_botRightTree != null) leafs.addAll(_getLeafs(_botRightTree!));
      if (_topRightTree != null) leafs.addAll(_getLeafs(_topRightTree!));
      return leafs;
    }
  }

  List<NodeData> _getLeafs(QuadTree tree) {
    final List<NodeData> leafs = [];
    final List<QuadTree> stack = [tree];

    while (stack.isNotEmpty) {
      final QuadTree current = stack.removeLast();
      if (!current.hasChildren) {
        leafs.addAll(current.leaf);
      } else {
        if (current.botLeftTree != null) stack.add(current.botLeftTree!);
        if (current.topLeftTree != null) stack.add(current.topLeftTree!);
        if (current.botRightTree != null) stack.add(current.botRightTree!);
        if (current.topRightTree != null) stack.add(current.topRightTree!);
      }
    }
    return leafs;
  }

  bool get hasChildren => _hasChildren;

  List<NodeData> get leaf => _leaf;

  QuadTree? get topLeftTree => _topLeftTree;

  QuadTree? get botLeftTree => _botLeftTree;

  QuadTree? get topRightTree => _topRightTree;

  QuadTree? get botRightTree => _botRightTree;
}
