import 'dart:typed_data';

enum PointPosition { left, right }

enum PointState { past, next, onWay, deleted }

// =============================================================================
// UI LAYER
// =============================================================================

/// Read-only projection of a side point for UI and external layers.
/// Contains setters for states, but works as a detached zero-cost wrapper
/// over a monolithic flat `Float64List` array of side points.
///
/// It stores 6 `double` values per point (48 bytes total, stride = 6):
/// * [0] lat (Latitude)
/// * [1] lng (Longitude)
/// * [2] absDist (Absolute 1D distance from start in meters)
/// * [3] orthoOffset (Perpendicular distance from route in meters)
/// * [4] routeInd (Route index, stored as double up to 2^53)
/// * [5] flags (Bitmask for enums and statuses, stored as double)
extension type UISidePointsBuffer(Float64List buffer) {
  /// Returns the amount of side points in the buffer.
  @pragma('vm:prefer-inline')
  int get length => buffer.length ~/ 6;

  /// Returns side point's latitude by it's index in the buffer.
  @pragma('vm:prefer-inline')
  double getLat(int index) => buffer[index * 6];

  /// Returns side point's longitude by it's index in the buffer.
  @pragma('vm:prefer-inline')
  double getLng(int index) => buffer[index * 6 + 1];

  /// Returns the remaining distance to the side point.
  /// Requires the user's current covered distance.
  @pragma('vm:prefer-inline')
  double routeDist(int index, double coveredDist) =>
      buffer[index * 6 + 2] - coveredDist;

  /// Returns the physical travel distance from the user to the side point.
  /// Consists of the remaining route path plus the orthogonal offset.
  /// Requires the user's current covered distance.
  @pragma('vm:prefer-inline')
  double travelDist(int index, double coveredDist) {
    final double remaining = buffer[index * 6 + 2] - coveredDist;
    final double ortho = buffer[index * 6 + 3];
    return remaining + ortho;
  }

  /// Returns side point's absolute distance on route by it's index in the buffer.
  @pragma('vm:prefer-inline')
  double getAbsoluteDist(int index) => buffer[index * 6 + 2];

  /// Returns side point's orthogonal offset by it's index in the buffer.
  @pragma('vm:prefer-inline')
  double getOrthoOffset(int index) => buffer[index * 6 + 3];

  /// Returns side point's route point index by it's index in the buffer.
  @pragma('vm:prefer-inline')
  int getRouteInd(int index) => buffer[index * 6 + 4].toInt();

  /// Returns side point's state by it's index in the buffer.
  @pragma('vm:prefer-inline')
  PointState getState(int index) {
    final int flags = buffer[index * 6 + 5].toInt();
    // Apply a bitwise AND mask (0x3 or 00000011) to isolate the first 2 bits
    return PointState.values[flags & 0x3];
  }

  /// Sets side point's state by it's index in the buffer.
  @pragma('vm:prefer-inline')
  void setState(int index, PointState newState) {
    final int offset = index * 6 + 5;
    int flags = buffer[offset].toInt();
    // 1. Clear the first 2 bits using inverted mask ~0x3 (11111100)
    // 2. Write the new state index using bitwise OR
    flags = (flags & ~0x3) | newState.index;
    buffer[offset] = flags.toDouble();
  }

  /// Returns side point's position by it's index in the buffer.
  @pragma('vm:prefer-inline')
  PointPosition getPosition(int index) {
    final int flags = buffer[index * 6 + 5].toInt();
    // 1. Right-shift by 2 to drop the state bits
    // 2. Apply a bitwise AND mask (0x1 or 00000001) to isolate the position bit
    return PointPosition.values[(flags >> 2) & 0x1];
  }

  /// Sets side point's position by it's index in the buffer.
  @pragma('vm:prefer-inline')
  void setPosition(int index, PointPosition newPos) {
    final int offset = index * 6 + 5;
    int flags = buffer[offset].toInt();
    // 1. Clear the 3rd bit using inverted mask ~0x4 (11111011)
    // 2. Shift the new position index left by 2 and write using bitwise OR
    flags = (flags & ~0x4) | (newPos.index << 2);
    buffer[offset] = flags.toDouble();
  }

  /// Checks if side point is a way point by it's index in the buffer.
  @pragma('vm:prefer-inline')
  bool getIsWayPoint(int index) {
    final int flags = buffer[index * 6 + 5].toInt();
    // 1. Right-shift by 3 to drop the state and position bits
    // 2. Apply a bitwise AND mask (0x1 or 00000001) to isolate the WayPoint bit
    return ((flags >> 3) & 0x1) == 1;
  }
}

// =============================================================================
// ENGINE STATES LAYER
// =============================================================================

/// Zero-cost engine abstraction over a `Uint8List` array of side point states.
///
/// Implements the Structure of Arrays (SoA) pattern by isolating mutable
/// bitmasks from static spatial data, maximizing L1 cache hits during hot-path
/// routing loops. The underlying buffer must be hardware-aligned to 8 bytes
/// (allocated via `Float64List`) to guarantee memory safety during
/// cross-isolate zero-copy transfers and file serialization.
///
/// Stride: 1 byte per point containing packed bit flags:
/// * bits [0-1]: [PointState] enum index (max value 3)
/// * bit [2]: [PointPosition] enum index (0 = left, 1 = right)
/// * bit [3]: isWayPoint boolean flag (0 = false, 1 = true)
/// * bits [4-7]: Unused / Reserved
extension type SidePointStates(Uint8List buffer) {
  /// Returns the amount of side points states in the buffer. Up to 7 last
  /// digits can be placeholders to allow conversion to `Float64List`.
  @pragma('vm:prefer-inline')
  int get length => buffer.length;

  /// Returns how many 64 bits numbers can be stored in the buffer.
  @pragma('vm:prefer-inline')
  int get lengthIn64Bits => buffer.length ~/ 8;

  /// Returns all side point's flags as int by it's index in the buffer.
  @pragma('vm:prefer-inline')
  int getAll(int index) => buffer[index];

  /// Sets all side point's flags at once by it's index in the buffer.
  @pragma('vm:prefer-inline')
  void setAll(
      int index, PointState state, PointPosition position, bool isWayPoint) {
    final int flags;
    if (isWayPoint) {
      flags = (1 << 3) | (position.index << 2) | state.index;
    } else {
      flags = (0 << 3) | (position.index << 2) | state.index;
    }
    buffer[index] = flags;
  }

  /// Returns side point's state by it's index in the buffer.
  @pragma('vm:prefer-inline')
  PointState getState(int index) => PointState.values[buffer[index] & 0x3];

  /// Sets side point's state by it's index in the buffer.
  @pragma('vm:prefer-inline')
  void setState(int index, PointState newState) {
    buffer[index] = (buffer[index] & ~0x3) | newState.index;
  }

  /// Returns side point's position by it's index in the buffer.
  @pragma('vm:prefer-inline')
  PointPosition getPosition(int index) =>
      PointPosition.values[(buffer[index] >> 2) & 0x1];

  /// Sets side point's position by it's index in the buffer.
  @pragma('vm:prefer-inline')
  void setPosition(int index, PointPosition newPos) {
    buffer[index] = (buffer[index] & ~0x4) | (newPos.index << 2);
  }

  /// Checks if side point is a way point by it's index in the buffer.
  @pragma('vm:prefer-inline')
  bool getIsWayPoint(int index) => ((buffer[index] >> 3) & 0x1) == 1;

  /// Sets the waypoint flag for a side point by its index in the buffer.
  @pragma('vm:prefer-inline')
  void setIsWayPoint(int index, bool value) {
    if (value) {
      buffer[index] = (buffer[index] & ~0x8) | (1 << 3);
    } else {
      buffer[index] = (buffer[index] & ~0x8) | (0 << 3);
    }
  }
}

// =============================================================================
// ENGINE SPATIAL LAYER
// =============================================================================

/// Zero-cost engine abstraction over a `Float64List` array of side point data.
///
/// Implements the Structure of Arrays (SoA) pattern by isolating static
/// geographic coordinates and projection metrics from mutable state flags. This
/// monolithic structure maximizes memory locality and is heavily optimized for
/// in-place 8-pass LSD Radix Sort operations during the route building phase.
///
/// Stride: 5 contiguous `double` values per point (40 bytes total):
/// * [0] lat (Latitude)
/// * [1] lng (Longitude)
/// * [2] absDist (Absolute 1D distance from start in meters)
/// * [3] orthoOffset (Perpendicular distance from the route in meters)
/// * [4] routeInd (Route segment index, safely stored as a double up to 2^53)
extension type RawSidePointsBuffer(Float64List buffer) {
  /// Returns the amount of side points in the buffer.
  @pragma('vm:prefer-inline')
  int get length => buffer.length ~/ 5;

  /// Returns how many 64 bits numbers can be stored in the buffer.
  @pragma('vm:prefer-inline')
  int get lengthIn64Bits => buffer.length;

  /// Sets all side point data by it's index in the buffer.
  @pragma('vm:prefer-inline')
  void setSidePoint(
    int index, {
    required double lat,
    required double lng,
    required double absDist,
    required double orthoOffset,
    required int routeInd,
  }) {
    final int offset = index * 5;
    buffer[offset] = lat;
    buffer[offset + 1] = lng;
    buffer[offset + 2] = absDist;
    buffer[offset + 3] = orthoOffset;
    buffer[offset + 4] = routeInd.toDouble();
  }

  /// Returns side point's latitude by it's index in the buffer.
  @pragma('vm:prefer-inline')
  double getLat(int index) => buffer[index * 5];

  /// Returns side point's longitude by it's index in the buffer.
  @pragma('vm:prefer-inline')
  double getLng(int index) => buffer[index * 5 + 1];

  /// Returns side point's absolute distance on route by it's index in the buffer.
  @pragma('vm:prefer-inline')
  double getAbsDist(int index) => buffer[index * 5 + 2];

  /// Returns side point's orthogonal offset by it's index in the buffer.
  @pragma('vm:prefer-inline')
  double getOrthoOffset(int index) => buffer[index * 5 + 3];

  /// Returns side point's route point index by it's index in the buffer.
  @pragma('vm:prefer-inline')
  int getRouteInd(int index) => buffer[index * 5 + 4].toInt();

  /// Performs a logical (soft) deletion of a target point.
  /// Scans the buffer for matching coordinates and writes the `deleted` flag
  /// directly into the parallel state buffer, avoiding expensive memory shifts.
  @pragma('vm:prefer-inline')
  void removeByPoint(double lat, double lng, SidePointStates states) {
    final int count = length;
    for (int i = 0; i < count; i++) {
      if (getLat(i) == lat && getLng(i) == lng) {
        states.setState(i, PointState.deleted);
        break;
      }
    }
  }

  /// Sorts the points strictly by their absolute distance along the route.
  ///
  /// Utilizes an 8-pass LSD Radix Sort optimized for IEEE 754 Little-Endian floats.
  ///
  /// Returns a NEW buffer instance containing the sorted spatial data.
  /// The old buffer is not mutated and should be discarded.
  ///
  /// * Performance: O(N). Avoids heavy in-place swaps of 40-byte blocks.
  RawSidePointsBuffer align() {
    final int pointAmount = length;
    if (pointAmount <= 1) return this;

    final Uint64List keys = Uint64List(pointAmount);
    final Int32List indices = Int32List(pointAmount);
    final Uint64List tmpKeys = Uint64List(pointAmount);
    final Int32List tmpIndices = Int32List(pointAmount);

    final Float64List keysFloatView = Float64List.view(keys.buffer);
    final Int32List globalCounts = Int32List(2048);

    for (int i = 0; i < pointAmount; i++) {
      keysFloatView[i] = buffer[i * 5 + 2];
      indices[i] = i;

      final int key = keys[i];

      globalCounts[key & 0xFF]++;
      globalCounts[256 + ((key >>> 8) & 0xFF)]++;
      globalCounts[512 + ((key >>> 16) & 0xFF)]++;
      globalCounts[768 + ((key >>> 24) & 0xFF)]++;
      globalCounts[1024 + ((key >>> 32) & 0xFF)]++;
      globalCounts[1280 + ((key >>> 40) & 0xFF)]++;
      globalCounts[1536 + ((key >>> 48) & 0xFF)]++;
      globalCounts[1792 + ((key >>> 56) & 0xFF)]++;
    }

    Uint64List currentKeys = keys;
    Int32List currentIndices = indices;
    Uint64List nextKeys = tmpKeys;
    Int32List nextIndices = tmpIndices;

    for (int pass = 0; pass < 8; pass++) {
      final int shift = pass * 8;
      final int countsOffset = pass * 256;

      final int firstElementBucket = (currentKeys[0] >>> shift) & 0xFF;
      if (globalCounts[countsOffset + firstElementBucket] == pointAmount) {
        continue;
      }

      int offset = 0;
      for (int i = 0; i < 256; i++) {
        final int count = globalCounts[countsOffset + i];
        globalCounts[countsOffset + i] = offset;
        offset += count;
      }

      for (int i = 0; i < pointAmount; i++) {
        final int value = currentKeys[i];
        final int bucket = (value >>> shift) & 0xFF;
        final int destIndex = globalCounts[countsOffset + bucket]++;

        nextKeys[destIndex] = value;
        nextIndices[destIndex] = currentIndices[i];
      }

      final Uint64List swapK = currentKeys;
      currentKeys = nextKeys;
      nextKeys = swapK;

      final Int32List swapI = currentIndices;
      currentIndices = nextIndices;
      nextIndices = swapI;
    }

    final Float64List sortedSpatial = Float64List(pointAmount * 5);
    for (int i = 0; i < pointAmount; i++) {
      final int srcInd = currentIndices[i];
      final int srcOffset = srcInd * 5;
      final int dstOffset = i * 5;

      sortedSpatial[dstOffset] = buffer[srcOffset];
      sortedSpatial[dstOffset + 1] = buffer[srcOffset + 1];
      sortedSpatial[dstOffset + 2] = buffer[srcOffset + 2];
      sortedSpatial[dstOffset + 3] = buffer[srcOffset + 3];
      sortedSpatial[dstOffset + 4] = buffer[srcOffset + 4];
    }

    return RawSidePointsBuffer(sortedSpatial);
  }
}
