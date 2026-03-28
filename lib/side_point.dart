import 'dart:typed_data';

enum PointPosition { left, right }

enum PointState { past, next, onWay, deleted }

/// Read-only projection of a side point for UI and external layers.
/// Contains no setters, preventing engine state mutation at compile time.
extension type ReadOnlySidePoint(Float64List buffer) {
  @pragma('vm:prefer-inline')
  double get lat => buffer[0];

  @pragma('vm:prefer-inline')
  double get lng => buffer[1];

  /// Returns the longitudinal distance (remaining route path).
  /// Requires the user's current covered distance.
  @pragma('vm:prefer-inline')
  double routeDist(double coveredDist) => buffer[2] - coveredDist;

  /// Returns the physical travel distance from the user to the point.
  /// Consists of the remaining route path plus the perpendicular offset.
  /// Requires the user's current covered distance.
  @pragma('vm:prefer-inline')
  double travelDist(double coveredDist) {
    final double remaining = buffer[2] - coveredDist;
    final double ortho = buffer[3];
    return remaining + ortho;
  }

  @pragma('vm:prefer-inline')
  double get orthoOffset => buffer[3];

  @pragma('vm:prefer-inline')
  int get routeInd => buffer[4].toInt();

  @pragma('vm:prefer-inline')
  PointState get state => PointState.values[buffer[5].toInt() & 0x3];

  @pragma('vm:prefer-inline')
  PointPosition get position =>
      PointPosition.values[(buffer[5].toInt() >> 2) & 0x1];

  @pragma('vm:prefer-inline')
  bool get isWayPoint => ((buffer[5].toInt() >> 3) & 0x1) == 1;
}

/// Zero-cost abstraction over a monolithic flat `Float64List` array of side points.
///
/// This extension type eliminates object overhead during intensive routing
/// calculations and enables zero-copy transfer between isolates using
/// `TransferableTypedData`, providing a high-performance Array of Structures (AoS)
/// memory layout.
///
/// It stores 6 contiguous `double` values per point (48 bytes total, stride = 6):
/// * [0] lat (Latitude)
/// * [1] lng (Longitude)
/// * [2] absDist (Absolute 1D distance from start in meters)
/// * [3] orthoOffset (Perpendicular distance from route in meters)
/// * [4] routeInd (Route index, stored as double up to 2^53)
/// * [5] flags (Bitmask for enums and statuses, stored as double)
extension type RawSidePointsBuffer(Float64List buffer) {
  // --- Initialization & Abstraction Lifecycle ---

  /// Returns the amount of elements, place for which allocated in buffer.
  @pragma('vm:prefer-inline')
  int get length => buffer.length ~/ 6;

  // --- Buffer Write Operations (Replaces OOP Constructors) ---

  /// Writes data for a single mapped side point directly into the buffer at [index].
  ///
  /// * Performance: High (Direct memory mapping, scalar operations).
  @pragma('vm:prefer-inline')
  void writeMapped(
    int index, {
    required double lat,
    required double lng,
    required double absDist,
    required double orthoOffset,
    required int routeInd,
    required PointPosition position,
    required PointState state,
    required bool isWayPoint,
  }) {
    final int offset = index * 6;
    buffer[offset] = lat;
    buffer[offset + 1] = lng;
    buffer[offset + 2] = absDist;
    buffer[offset + 3] = orthoOffset;
    buffer[offset + 4] = routeInd.toDouble();

    // Pack enums and booleans into a single integer flag
    // bit 0-1: PointState (max value 3)
    // bit 2: PointPosition (max value 1)
    // bit 3: isWayPoint (max value 1)
    final int flags;
    if (isWayPoint) {
      flags = (1 << 3) | (position.index << 2) | state.index;
    } else {
      flags = (0 << 3) | (position.index << 2) | state.index;
    }
    buffer[offset + 5] = flags.toDouble();
  }

  /// Writes spatial data for a side point directly into the buffer at [index].
  /// The flags are assumed to be zero-initialized.
  /// They must be mutated later during the mapping phase.
  @pragma('vm:prefer-inline')
  void writeUnmapped(
    int index, {
    required double lat,
    required double lng,
    required double absDist,
    required double orthoOffset,
    required int routeInd,
  }) {
    final int offset = index * 6;
    buffer[offset] = lat;
    buffer[offset + 1] = lng;
    buffer[offset + 2] = absDist;
    buffer[offset + 3] = orthoOffset;
    buffer[offset + 4] = routeInd.toDouble();
  }

  // --- Spatial Data Accessors (Immutable/Read-Only) ---

  /// Returns the latitude of the point at [index].
  @pragma('vm:prefer-inline')
  double getLat(int index) => buffer[index * 6];

  /// Returns the longitude of the point at [index].
  @pragma('vm:prefer-inline')
  double getLng(int index) => buffer[index * 6 + 1];

  /// Returns the accumulated 1D distance from the route start to this point
  /// projection in meters.
  @pragma('vm:prefer-inline')
  double getAbsDist(int index) => buffer[index * 6 + 2];

  /// Returns the perpendicular distance from the route to the physical point.
  @pragma('vm:prefer-inline')
  double getOrthoOffset(int index) => buffer[index * 6 + 3];

  /// Returns the route segment index this point belongs to.
  @pragma('vm:prefer-inline')
  int getRouteInd(int index) => buffer[index * 6 + 4].toInt();

  // --- Flags & Bitmask Accessors (Mutable/Read-Write) ---

  /// Returns the state of the point at [index] relative to the user's progress.
  @pragma('vm:prefer-inline')
  PointState getState(int index) {
    final int flags = buffer[index * 6 + 5].toInt();
    // Apply a bitwise AND mask (0x3 or 00000011) to isolate the first 2 bits
    return PointState.values[flags & 0x3];
  }

  /// Updates the state of the point at [index] using a bitwise mask.
  @pragma('vm:prefer-inline')
  void setState(int index, PointState newState) {
    final int offset = index * 6 + 5;
    int flags = buffer[offset].toInt();
    // 1. Clear the first 2 bits using inverted mask ~0x3 (11111100)
    // 2. Write the new state index using bitwise OR
    flags = (flags & ~0x3) | newState.index;
    buffer[offset] = flags.toDouble();
  }

  /// Returns the position of the point at [index] relative to the route vector.
  @pragma('vm:prefer-inline')
  PointPosition getPosition(int index) {
    final int flags = buffer[index * 6 + 5].toInt();
    // 1. Right-shift by 2 to drop the state bits
    // 2. Apply a bitwise AND mask (0x1 or 00000001) to isolate the position bit
    return PointPosition.values[(flags >> 2) & 0x1];
  }

  /// Updates the position of the point at [index] using a bitwise mask.
  @pragma('vm:prefer-inline')
  void setPosition(int index, PointPosition newPos) {
    final int offset = index * 6 + 5;
    int flags = buffer[offset].toInt();
    // 1. Clear the 3rd bit using inverted mask ~0x4 (11111011)
    // 2. Shift the new position index left by 2 and write using bitwise OR
    flags = (flags & ~0x4) | (newPos.index << 2);
    buffer[offset] = flags.toDouble();
  }

  /// Returns whether the point at [index] represents a WayPoint.
  @pragma('vm:prefer-inline')
  bool getIsWayPoint(int index) {
    final int flags = buffer[index * 6 + 5].toInt();
    // 1. Right-shift by 3 to drop the state and position bits
    // 2. Apply a bitwise AND mask (0x1 or 00000001) to isolate the WayPoint bit
    return ((flags >> 3) & 0x1) == 1;
  }

  /// Updates the WayPoint status of the point at [index] using a bitwise mask.
  @pragma('vm:prefer-inline')
  void setIsWayPoint(int index, bool value) {
    final int offset = index * 6 + 5;
    int flags = buffer[offset].toInt();
    // 1. Clear the 4th bit using inverted mask ~0x8 (11110111)
    // 2. Shift the boolean value (0 or 1) left by 3 and write using bitwise OR
    if (value) {
      flags = (flags & ~0x8) | (1 << 3);
    } else {
      flags = (flags & ~0x8) | (0 << 3);
    }
    buffer[offset] = flags.toDouble();
  }

  // --- Collection API ---

  /// Logically removes a point by applying the `deleted` state.
  ///
  /// * Warning: Uses exact float comparison `==`. May fail if coordinates
  /// suffer from IEEE 754 precision noise.
  @pragma('vm:prefer-inline')
  void removeByPoint(double targetLat, double targetLng) {
    final int count = buffer.length ~/ 6;
    for (int i = 0; i < count; i++) {
      if (getLat(i) == targetLat && getLng(i) == targetLng) {
        setState(i, PointState.deleted);
        break;
      }
    }
  }

  /// Sorts the points strictly by their 1D projection distance along the route (absDist).
  ///
  /// Utilizes an 8-pass LSD Radix Sort optimized for IEEE 754 Little-Endian floats.
  ///
  /// Returns a NEW buffer instance containing the sorted data.
  /// The old buffer is not mutated and should be discarded to be collected by GC.
  ///
  /// * Performance: O(N). Avoids heavy in-place swaps of 48-byte blocks.
  RawSidePointsBuffer align() {
    final int pointAmount = buffer.length ~/ 6;
    if (pointAmount <= 1) return this;

    final Uint64List keys = Uint64List(pointAmount);
    final Int32List indices = Int32List(pointAmount);
    final Uint64List tmpKeys = Uint64List(pointAmount);
    final Int32List tmpIndices = Int32List(pointAmount);

    final Float64List keysFloatView = Float64List.view(keys.buffer);
    final Int32List globalCounts = Int32List(2048);

    for (int i = 0; i < pointAmount; i++) {
      keysFloatView[i] = buffer[i * 6 + 2];
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

    final Float64List sortedBuffer = Float64List(buffer.length);
    for (int i = 0; i < pointAmount; i++) {
      final int srcOffset = currentIndices[i] * 6;
      final int dstOffset = i * 6;

      sortedBuffer[dstOffset] = buffer[srcOffset];
      sortedBuffer[dstOffset + 1] = buffer[srcOffset + 1];
      sortedBuffer[dstOffset + 2] = buffer[srcOffset + 2];
      sortedBuffer[dstOffset + 3] = buffer[srcOffset + 3];
      sortedBuffer[dstOffset + 4] = buffer[srcOffset + 4];
      sortedBuffer[dstOffset + 5] = buffer[srcOffset + 5];
    }

    return RawSidePointsBuffer(sortedBuffer);
  }

  /// Exports a flat snapshot of all active (non-deleted) points.
  /// Ready for TransferableTypedData isolate transmission.
  Float64List exportActiveSnapshot(int firstActiveIndex) {
    int aliveCount = 0;
    final int totalPoints = length;

    for (int i = firstActiveIndex; i < totalPoints; i++) {
      if (getState(i) != PointState.deleted) aliveCount++;
    }

    if (aliveCount == 0) return Float64List(0);

    final Float64List snapshot = Float64List(aliveCount * 6);
    int destOffset = 0;

    for (int i = firstActiveIndex; i < totalPoints; i++) {
      if (getState(i) != PointState.deleted) {
        final int srcOffset = i * 6;
        snapshot[destOffset++] = buffer[srcOffset];
        snapshot[destOffset++] = buffer[srcOffset + 1];
        snapshot[destOffset++] = buffer[srcOffset + 2];
        snapshot[destOffset++] = buffer[srcOffset + 3];
        snapshot[destOffset++] = buffer[srcOffset + 4];
        snapshot[destOffset++] = buffer[srcOffset + 5];
      }
    }
    return snapshot;
  }
}
