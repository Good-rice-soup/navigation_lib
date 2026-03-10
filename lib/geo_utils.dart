import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
/*
https://github.com/juanxme/google_maps_flutter_platform_interface/blob/master/lib/src/types/location.dart

peace of theory about Earth radius
https://en.wikipedia.org/wiki/Great-circle_distance
 */

//longitude and latitude are roughly
/*
decimal   places 	    rough scale
0         1.0         country
1 	      0.1         large city
2 	      0.01        town or village
3 	      0.001       neighborhood
4 	      0.0001      individual street
5 	      0.00001     individual trees
6 	      0.000001	  individual humans
*/

//Geohash Scale
/*
Geohash length 	Cell width 	Cell height
1 	              multiple countries
2 	              state - multiple states
3 	              multiple cities
4 	              average city
5 	              small town
6 	              neighborhood
7 	              individual street
8 	              small store
9 	              individual trees
10 	              individual humans
.....
*/

//Bounding box sizes
/*
Precision  Bounding box
1          <= 5000 km x 5000 km
2          <= 1250 km x 625 km
3          <= 156 km x 156 km
4          <= 39.1 km x 19.5 km
5          <= 4.89 km x 4.89 km
6          <= 1.22 km x 0.61 km
7          <= 153 m x 153 m
8          <= 38.2 m x 19.1 m
9          <= 4.77 m x 4.77 m
10         <= 1.19 m x 0.569 m
11         <= 149 mm x 149 mm
12         <= 37.2 mm x 18.6 mm
*/

const double earthRadiusInMeters = 6371009.0;
const double metersPerDegree = 111195.0797343687;

/// Converts degrees to radians by multiplying degrees on it.
const double deg2rad = pi / 180;

/// Converts radians to degrees by multiplying radians on it.
const double rad2deg = 180 / pi;

/// Calculates the distance between two geographical points using the
/// Equirectangular approximation. Returns the distance in meters.
///
/// This function optimized by accepting raw [double] coordinates. It is
/// designed for Struct of Arrays (SoA) architectures and tight loops and used
/// as high-performance alternative for haversine function on short distances.
///
/// * Algorithm: Projects spherical coordinates onto a local plane by scaling
/// the longitude difference based on the cosine of the mean latitude, then
/// applies the Pythagorean theorem.
///
/// * Performance: Very heigh (1 cos, 1 square root).
///
/// * Accuracy: High for short distances (less than a kilometre between points).
/// Error increases significantly over long distances or near the poles.
@pragma('vm:prefer-inline')
double getDistanceRaw(double lat1, double lon1, double lat2, double lon2) {
  // Convert degrees to radians for trigonometric functions
  final double rLat1 = lat1 * deg2rad;
  final double rLon1 = lon1 * deg2rad;
  final double rLat2 = lat2 * deg2rad;
  final double rLon2 = lon2 * deg2rad;

  // Calculate the difference in angular coordinates
  final double dLat = rLat2 - rLat1;
  final double dLon = rLon2 - rLon1;

  // Calculate the mean latitude to determine the local scale of longitudes
  final double averageLat = (rLat1 + rLat2) * 0.5;

  // Scale the longitude difference by the cosine of the mean latitude.
  // This flattens the spherical grid into a local Cartesian coordinate system.
  final double x = dLon * cos(averageLat);

  // Apply the Pythagorean theorem on the projected flat plane
  final double squaredDist = (x * x) + (dLat * dLat);

  // Extract the root to get the angular distance, then multiply by Earth's
  // radius to convert the result into physical meters.
  return earthRadiusInMeters * sqrt(squaredDist);
}

/// Calculates the distance between two geographical points using the
/// Equirectangular approximation. Returns the distance in meters.
///
/// This is a high-performance alternative to the Haversine formula for short
/// distances.
///
/// * Algorithm: Projects spherical coordinates onto a local plane by scaling
/// the longitude difference based on the cosine of the mean latitude, then
/// applies the Pythagorean theorem.
///
/// * Performance: Very high (1 cos, 1 square root).
///
/// * Accuracy: High for short distances (less than a kilometre between points).
/// Error increases significantly over long distances or near the poles.
@pragma('vm:prefer-inline')
double getDistance(LatLng p1, LatLng p2) {
  // Convert degrees to radians for trigonometric functions
  final double rLat1 = p1.latitude * deg2rad;
  final double rLon1 = p1.longitude * deg2rad;
  final double rLat2 = p2.latitude * deg2rad;
  final double rLon2 = p2.longitude * deg2rad;

  // Calculate the difference in angular coordinates
  final double dLat = rLat2 - rLat1;
  final double dLon = rLon2 - rLon1;

  // Calculate the mean latitude to determine the local scale of longitudes
  final double meanLat = (rLat1 + rLat2) * 0.5;

  // Scale the longitude difference by the cosine of the mean latitude.
  // This flattens the spherical grid into a local Cartesian coordinate system.
  final double x = dLon * cos(meanLat);

  // Apply the Pythagorean theorem on the projected flat plane
  final double squaredDist = (x * x) + (dLat * dLat);

  // Extract the root to get the angular distance, then multiply by Earth's
  // radius to convert the result into physical meters.
  return earthRadiusInMeters * sqrt(squaredDist);
}

/// Calculates the great-circle distance between two geographical points using
/// the Haversine formula. Returns the distance in meters.
///
/// This function provides high accuracy for long distances across the Earth's
/// surface, treating the planet as a perfect sphere with a radius of
/// [earthRadiusInMeters].
///
/// * Algorithm: Uses the Haversine formula to calculate the shortest distance
/// over the earth's surface between the points.
///
/// * Performance: Low (2 sin, 2 cos, 1 asin, 1 square root).
///
/// * Accuracy: High for long distances. Should be used when precision over
/// distances of more than 5 kilometers is strictly required.
@pragma('vm:prefer-inline')
double getDistanceHaversine(LatLng p1, LatLng p2) {
  const double earthRadius = earthRadiusInMeters;

  // Convert degrees to radians
  final double lat1 = p1.latitude * deg2rad;
  final double lon1 = p1.longitude * deg2rad;
  final double lat2 = p2.latitude * deg2rad;
  final double lon2 = p2.longitude * deg2rad;

  final double dLat = lat2 - lat1;
  final double dLon = lon2 - lon1;

  // Calculate the square of half the chord length between the points
  final double sinHalfDLat = sin(dLat / 2);
  final double sinHalfDLon = sin(dLon / 2);

  final double haversinLat = sinHalfDLat * sinHalfDLat;
  final double haversinLon = sinHalfDLon * sinHalfDLon;

  // Pre-calculate cosines
  final double cosLat1 = cos(lat1);
  final double cosLat2 = cos(lat2);

  final double a = haversinLat + haversinLon * cosLat1 * cosLat2;

  // Protect against rounding errors that could cause 'a' to exceed 1.0,
  // resulting in a NaN output from asin()
  final double sqrtA = sqrt(a);
  final double c = 2 * asin(sqrtA.clamp(0, 1));

  return earthRadius * c;
}

/// Degrees to radians.
double toRadians(double deg) => deg * deg2rad;

/// Radians to degrees.
double toDegrees(double rad) => rad * rad2deg;

/// Convert meters to latitude degrees.
double metersToLatDegrees(double meters) => meters / metersPerDegree;

/// Convert meters to longitude degrees using latitude.
double metersToLngDegrees(double meters, double latitude) =>
    meters / (metersPerDegree * cos(toRadians(latitude)));

/// Returns a skew production between a vector AB and point C. If skew production (sk):
/// - sk > 0, C is on the left relative to the vector.
/// - sk == 0, C is on the vector/directly along the vector/behind the vector.
/// - sk < 0, C is on the right relative to the vector.
/// ``````
/// https://acmp.ru/article.asp?id_text=172
double skewProduction(LatLng A, LatLng B, LatLng C) {
// Remember that Lat is y on OY and Lng is x on OX => LatLng is (y,x), not (x,y)
  return ((B.longitude - A.longitude) * (C.latitude - A.latitude)) -
      ((B.latitude - A.latitude) * (C.longitude - A.longitude));
}

LatLng getPointProjection(LatLng currLoc, LatLng start, LatLng end) {
  final double dLat = end.latitude - start.latitude;
  final double dLng = end.longitude - start.longitude;

  if (dLat == 0 && dLng == 0) throw ArgumentError('Start and end are same');

  // start(x1, y1), end(x2, y2), point(x0, y0)
  final double x0 = currLoc.latitude;
  final double x1 = start.latitude;
  final double y0 = currLoc.longitude;
  final double y1 = start.longitude;

  if (dLng == 0 && dLat != 0) return LatLng(x0, y1);
  if (dLng != 0 && dLat == 0) return LatLng(x1, y0);

  // coefficients in line equations system Ax + By + C = 0
  // A = y2 - y1, B = x2 - x1
  final double aa = dLng * dLng; // A^2
  final double bb = dLat * dLat; // B^2
  final double ab = dLng * dLat;
  final double denominator = aa + bb;

  final double y = (bb * y1 + ab * (x0 - x1) + aa * y0) / denominator;
  final double x = (aa * x1 + ab * (y0 - y1) + bb * x0) / denominator;

  return LatLng(x, y);
}

LatLngBounds expandBounds(LatLngBounds bounds, [double expFactor = 1]) {
  final double lat =
      (bounds.northeast.latitude - bounds.southwest.latitude).abs();
  final double lng =
      (bounds.northeast.longitude - bounds.southwest.longitude).abs();
  final LatLng southwest = LatLng(
    bounds.southwest.latitude - (lat * (expFactor - 1) / 2),
    (bounds.southwest.longitude - (lng * (expFactor - 1) / 2))
        .clamp(-180, 179.9999999999),
  );
  final LatLng northeast = LatLng(
    bounds.northeast.latitude + (lat * (expFactor - 1) / 2),
    (bounds.northeast.longitude + (lng * (expFactor - 1) / 2))
        .clamp(-180, 179.9999999999),
  );

  return LatLngBounds(southwest: southwest, northeast: northeast);
}
