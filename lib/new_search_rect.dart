import 'dart:math';
import 'dart:typed_data';

import 'geo_utils.dart';

/// Zero-cost abstraction over a flat `Float64List` array for search rectangles.
///
/// This extension type completely erases the object overhead at compile time,
/// providing high-performance Struct of Arrays (SoA) memory layout.
/// It stores 10 contiguous `double` values per segment:
/// * [0] normX, [1] normY (Normalized direction vector)
/// * [2] a.lat, [3] a.lng (Bottom-Right corner)
/// * [4] b.lat, [5] b.lng (Bottom-Left corner)
/// * [6] c.lat, [7] c.lng (Top-Left corner)
/// * [8] d.lat, [9] d.lng (Top-Right corner)
extension type SearchRectBuffer(Float64List buffer) {
  /// Allocates the memory buffer for the specified amount of segments.
  @pragma('vm:prefer-inline')
  SearchRectBuffer.allocate(int segmentsCount)
      : buffer = Float64List(segmentsCount * 10);

  /// Initializes the buffer directly from an existing memory block, typically
  /// after reading from a provided raw data.
  @pragma('vm:prefer-inline')
  SearchRectBuffer.fromBytes(Float64List bytesBuffer)
      : buffer = bytesBuffer;

  /// Calculates the search rectangle for a geographical segment and stores the
  /// vertices and direction vector in the flat buffer.
  ///
  /// * Algorithm: Projects spherical coordinates to a local plane using the
  /// Equirectangular approximation. Extends the segment forwards/backwards
  /// by [rectExt], calculates a perpendicular normal, and expands sideways
  /// by [rectWidth], adjusting longitude scale via the cosine of the latitude.
  ///
  /// * Performance: High (1 sqrt, 3 cos + allocates 0 objects).
  @pragma('vm:prefer-inline')
  void calculateAndSet(
    int segmentIndex,
    double startLat,
    double startLng,
    double endLat,
    double endLng,
    double rectWidth,
    double rectExt,
  ) {
    final int offset = segmentIndex * 10;

    // finding an average latitude for correct meridian convergence coefficient
    final double avgLat = (startLat + endLat) * 0.5;
    final double cosAvg = cos(avgLat * deg2rad);

    // finding segment vector and it's length
    final double vLat = endLat - startLat;
    final double vLng = (endLng - startLng) * cosAvg;
    final double inversedLen = 1.0 / sqrt(vLat * vLat + vLng * vLng);

    // vector normalisation
    final double normLat = vLat * inversedLen;
    final double normLng = vLng * inversedLen;
    buffer[offset] = normLat;
    buffer[offset + 1] = normLng;

    // converting width and extension from meters to degrees (for latitude and
    // equator it is always meters / 111 111 meters)
    final double width = rectWidth / metersPerDegree;
    final double ext = rectExt / metersPerDegree;

    // segment prolonging vector
    final double extLat = normLat * ext;
    final double extLng = normLng * ext;

    // segment perpendicular vector
    final double perpLat = normLng * width;
    final double perpLng = -normLat * width;

    // convert latitude from degrees to radians and take cosine to compute
    // meridian convergence coefficient
    final double inversedCosStart = 1 / cos(startLat * deg2rad);
    final double inversedCosEnd = 1 / cos(endLat * deg2rad);

    // calculate points and longitude parts of perpendicular
    final double startExtLat = startLat - extLat;
    final double startExtLng = startLng - (extLng * inversedCosStart);

    final double endExtLat = endLat + extLat;
    final double endExtLng = endLng + (extLng * inversedCosEnd);

    final double perpLngStart = perpLng * inversedCosStart;
    final double perpLngEnd = perpLng * inversedCosEnd;

    // bottom-right corner
    buffer[offset + 2] = endExtLat + perpLat;
    buffer[offset + 3] = endExtLng + perpLngEnd;

    // bottom-left corner
    buffer[offset + 4] = endExtLat - perpLat;
    buffer[offset + 5] = endExtLng - perpLngEnd;

    // top-left corner
    buffer[offset + 6] = startExtLat - perpLat;
    buffer[offset + 7] = startExtLng - perpLngStart;

    // top-right corner
    buffer[offset + 8] = startExtLat + perpLat;
    buffer[offset + 9] = startExtLng + perpLngStart;
  }

  /// Returns the normalized direction vector of the segment.
  @pragma('vm:prefer-inline')
  ({double lat, double lng}) getNormalisedSegmVect(int segmentIndex) {
    final int offset = segmentIndex * 10;
    return (lat: buffer[offset], lng: buffer[offset + 1]);
  }

  /// Checks if a geographical point lies within the search rectangle of a segment.
  ///
  /// * Algorithm: Ray Casting (Even-Odd rule). Casts a virtual ray from the
  /// point along the latitude axis and counts intersections with polygon edges.
  /// An odd number of intersections indicates the point is strictly inside.
  ///
  /// * Performance: High (scalar operations reading from the contiguous memory
  /// buffer + no object creation).
  @pragma('vm:prefer-inline')
  bool isPointInRect(int segmentIndex, double pLat, double pLng) {
    // skip the normal vector
    final int offset = (segmentIndex * 10) + 2;
    int intersections = 0;

    for (int i = 0; i < 4; i++) {
      final int indA = offset + (i * 2);
      final int indB = offset + (((i + 1) % 4) * 2);

      final double aLat = buffer[indA];
      final double aLng = buffer[indA + 1];
      final double bLat = buffer[indB];
      final double bLng = buffer[indB + 1];

      // if ray crosses the longitude (vertical line)
      if ((aLng > pLng) != (bLng > pLng)) {
        // try to find exact cross point's latitude (horizontal line)
        final double intersect =
            (bLat - aLat) * (pLng - aLng) / (bLng - aLng) + aLat;
        // if intersection was in front of the ray, we count it
        if (pLat > intersect) intersections++;
      }
    }
    return intersections.isOdd;
  }
}
