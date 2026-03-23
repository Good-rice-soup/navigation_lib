import 'dart:typed_data';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

enum PointPosition { left, right }

enum PointState { past, next, onWay }

class SidePoint {
  SidePoint({
    required this.point,
    required this.routeInd,
    required this.position,
    required this.state,
    required this.dist,
  });

  final LatLng point;
  final int routeInd;
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
      point: point,
      routeInd: routeInd,
      position: position,
      state: state,
      dist: dist,
    );
  }
}

/// Zero-cost abstraction over a flat `Float64List` array for a side point.
///
/// This extension type eliminates object overhead during intensive routing
/// calculations and enables zero-copy transfer between isolates using
/// `TransferableTypedData`, providing high-performance Struct of Arrays (SoA)
/// memory layout.
///
/// It stores 5 contiguous `double` values per point (40 bytes total):
/// * [0] lat (Latitude)
/// * [1] lng (Longitude)
/// * [2] dist (Distance from start in meters)
/// * [3] routeInd (Route index, stored as double up to 2^53)
/// * [4] flags (Bitmask for enums and statuses, stored as double)
extension type RawSidePoint(Float64List buffer) {
  /// Allocates a 40-byte memory buffer for a single side point and packs
  /// its data.
  ///
  /// * Performance: High (1 allocation, scalar operations).
  @pragma('vm:prefer-inline')
  RawSidePoint.create({
    required double lat,
    required double lng,
    required double dist,
    required int routeInd,
    required PointPosition position,
    required PointState state,
    required bool isWayPoint,
  }) : buffer = Float64List(5) {
    // 1. Store primitive coordinates and distances directly
    buffer[0] = lat;
    buffer[1] = lng;
    buffer[2] = dist;
    buffer[3] = routeInd.toDouble();

    // 2. Pack enums and booleans into a single integer flag
    // bit 0-1: PointState (max value 2)
    // bit 2: PointPosition (max value 1)
    // bit 3: isWayPoint (max value 1)
    final int flags;
    if (isWayPoint) {
      flags = (1 << 3) | (position.index << 2) | state.index;
    } else {
      flags = (0 << 3) | (position.index << 2) | state.index;
    }

    // 3. Cast to double for homogeneous array storage
    buffer[4] = flags.toDouble();
  }

  /// Allocates a buffer using only spatial data.
  ///
  /// The flags buffer `buffer[4]` is automatically zero-initialized by the VM.
  /// These flags must be mutated later during the mapping phase.
  @pragma('vm:prefer-inline')
  RawSidePoint.addUnmapped({
    required double lat,
    required double lng,
    required double dist,
    required int routeInd,
  }) : buffer = Float64List(5) {
    buffer[0] = lat;
    buffer[1] = lng;
    buffer[2] = dist;
    buffer[3] = routeInd.toDouble();
  }

  /// Returns the latitude of the point.
  @pragma('vm:prefer-inline')
  double get lat => buffer[0];

  /// Returns the longitude of the point.
  @pragma('vm:prefer-inline')
  double get lng => buffer[1];

  /// Returns the accumulated distance from the route start to this point
  /// in meters.
  @pragma('vm:prefer-inline')
  double get dist => buffer[2];

  /// Updates the accumulated distance.
  @pragma('vm:prefer-inline')
  set dist(double value) => buffer[2] = value;

  /// Returns the route segment index this point belongs to.
  @pragma('vm:prefer-inline')
  int get routeInd => buffer[3].toInt();

  /// Returns the state of the point relative to the user's progress.
  @pragma('vm:prefer-inline')
  PointState get state {
    // 1. Extract the integer flag from the double buffer
    final int flags = buffer[4].toInt();
    // 2. Apply a bitwise AND mask (0x3 or 00000011) to isolate the first 2 bits
    return PointState.values[flags & 0x3];
  }

  /// Updates the state of the point using a bitwise mask.
  @pragma('vm:prefer-inline')
  set state(PointState newState) {
    int flags = buffer[4].toInt();
    // 1. Clear the first 2 bits using inverted mask ~0x3 (11111100)
    // 2. Write the new state index using bitwise OR
    flags = (flags & ~0x3) | newState.index;
    buffer[4] = flags.toDouble();
  }

  /// Returns the position of the point relative to the route vector.
  @pragma('vm:prefer-inline')
  PointPosition get position {
    final int flags = buffer[4].toInt();
    // 1. Right-shift by 2 to drop the state bits
    // 2. Apply a bitwise AND mask (0x1 or 00000001) to isolate the position bit
    return PointPosition.values[(flags >> 2) & 0x1];
  }

  /// Updates the position of the point using a bitwise mask.
  @pragma('vm:prefer-inline')
  set position(PointPosition newPos) {
    int flags = buffer[4].toInt();
    // 1. Clear the 3rd bit using inverted mask ~0x4 (11111011)
    // 2. Shift the new position index left by 2 and write using bitwise OR
    flags = (flags & ~0x4) | (newPos.index << 2);
    buffer[4] = flags.toDouble();
  }

  /// Returns whether this point represents a WayPoint.
  @pragma('vm:prefer-inline')
  bool get isWayPoint {
    final int flags = buffer[4].toInt();
    // 1. Right-shift by 3 to drop the state and position bits
    // 2. Apply a bitwise AND mask (0x1 or 00000001) to isolate the WayPoint bit
    return ((flags >> 3) & 0x1) == 1;
  }

  /// Updates the WayPoint status of the point using a bitwise mask.
  @pragma('vm:prefer-inline')
  set isWayPoint(bool value) {
    int flags = buffer[4].toInt();
    // 1. Clear the 4th bit using inverted mask ~0x8 (11110111)
    // 2. Shift the boolean value (0 or 1) left by 3 and write using bitwise OR
    if (value) {
      flags = (flags & ~0x8) | (1 << 3);
    } else {
      flags = (flags & ~0x8) | (0 << 3);
    }
    buffer[4] = flags.toDouble();
  }

  /// Materializes the lightweight buffer into a heavy OOP [SidePoint] instance.
  ///
  /// * Performance: Low (allocates memory for [SidePoint] and [LatLng]).
  /// Should only be called when crossing the boundary from DAO
  /// to UI/Business Logic.
  SidePoint toPublicSidePoint() {
    return SidePoint(
      point: LatLng(lat, lng),
      routeInd: routeInd,
      position: position,
      state: state,
      dist: dist,
    );
  }

  /// Returns the underlying typed data buffer.
  ///
  /// Useful for zero-copy transfers across Dart Isolates
  /// via `TransferableTypedData`.
  @pragma('vm:prefer-inline')
  Float64List get rawBuffer => buffer;
}

/// Zero-cost abstraction over a collection of [RawSidePoint].
///
/// Acts as an encapsulated buffer at compile time, resolving to a simple
/// `List<RawSidePoint>` at runtime. Designed to facilitate a future seamless
/// transition to a monolithic `Float64List` DOD array without altering the
/// public API.
extension type RawSidePointsBuffer(List<RawSidePoint> _points) {
  /// Initializes an empty buffer.
  @pragma('vm:prefer-inline')
  RawSidePointsBuffer.empty() : _points = [];

  /// Restores the collection from a contiguous `Float64List`.
  ///
  /// * Algorithm: Uses `Float64List.sublistView` to create lightweight slice
  /// lenses for each point without allocating or copying new memory blocks.
  ///
  /// * Performance: High (O(N), creates views only).
  factory RawSidePointsBuffer.fromFlatBuffer(Float64List flatBuffer) {
    final int pointsCount = flatBuffer.length ~/ 5;

    final list = List<RawSidePoint>.generate(
      pointsCount,
      (i) {
        final int offset = i * 5;
        return RawSidePoint(
            Float64List.sublistView(flatBuffer, offset, offset + 5));
      },
    );

    return RawSidePointsBuffer(list);
  }

  // --- Collection API ---

  @pragma('vm:prefer-inline')
  void add(RawSidePoint point) => _points.add(point);

  @pragma('vm:prefer-inline')
  void removeAt(int index) => _points.removeAt(index);

  @pragma('vm:prefer-inline')
  void removeByPoint(double targetLat, double targetLng) {
    _points.removeWhere((p) => p.lat == targetLat && p.lng == targetLng);
  }

  @pragma('vm:prefer-inline')
  int get length => _points.length;

  @pragma('vm:prefer-inline')
  bool get isEmpty => _points.isEmpty;

  @pragma('vm:prefer-inline')
  bool get isNotEmpty => _points.isNotEmpty;

  @pragma('vm:prefer-inline')
  RawSidePoint operator [](int index) => _points[index];

  @pragma('vm:prefer-inline')
  void operator []=(int index, RawSidePoint value) => _points[index] = value;

  // --- Core Logic ---

  /// Sorts the points primarily by route index and secondarily by distance.
  ///
  /// * Algorithm: Falls back to Dart's standard `List.sort` for stable performance
  /// on small-to-medium arrays. First index (0) is sorted in descending order
  /// by distance, all subsequent indices in ascending order.
  void align() {
    _points.sort((a, b) {
      final int indCompare = a.routeInd.compareTo(b.routeInd);
      if (indCompare != 0) return indCompare;
      if (a.routeInd == 0) return b.dist.compareTo(a.dist);
      return a.dist.compareTo(b.dist);
    });
  }

  // --- Export ---

  /// Glues all isolated side point buffers into a single
  /// contiguous `Float64List`.
  ///
  /// * Algorithm: Allocates a monolithic memory block and rapidly copies
  /// 5-element blocks via `setAll`. Ideal for file serialization (SoA) or
  /// packing into `TransferableTypedData`.
  ///
  /// * Performance: O(N) linear copy.
  Float64List toFlatBuffer() {
    final int totalLength = _points.length * 5;
    final Float64List flat = Float64List(totalLength);

    for (int i = 0; i < _points.length; i++) {
      flat.setAll(i * 5, _points[i].rawBuffer);
    }

    return flat;
  }
}
