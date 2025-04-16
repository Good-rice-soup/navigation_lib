import 'dart:math';

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
/*
https://github.com/juanxme/google_maps_flutter_platform_interface/blob/master/lib/src/types/location.dart

peace of theory about Earth radius
https://en.wikipedia.org/wiki/Great-circle_distance
 */

const double earthRadiusInMeters = 6371009.0;
const double metersPerDegree = 111195.0797343687;

/// Get distance between two points.
double getDistance({required LatLng p1, required LatLng p2}) {
  const double earthRadius = earthRadiusInMeters;

  final double lat1 = p1.latitude;
  final double lon1 = p1.longitude;

  final double lat2 = p2.latitude;
  final double lon2 = p2.longitude;

  final double dLat = toRadians(lat2 - lat1);
  final double dLon = toRadians(lon2 - lon1);

  final double haversinLat = pow(sin(dLat / 2), 2).toDouble();
  final double haversinLon = pow(sin(dLon / 2), 2).toDouble();

  final double a =
      haversinLat + haversinLon * cos(toRadians(lat1)) * cos(toRadians(lat2));
  final double c = 2 * asin(sqrt(a));

  return earthRadius * c;
}

/// Degrees to radians.
double toRadians(double deg) {
return deg * (pi / 180);
}

/// Radians to degrees.
double toDegrees(double rad) {
return rad * (180 / pi);
}

/// Convert meters to latitude degrees.
double metersToLatDegrees(double meters) {
  return meters / metersPerDegree;
}

/// Convert meters to longitude degrees using latitude.
double metersToLngDegrees(double meters, double latitude) {
  return meters / (metersPerDegree * cos(toRadians(latitude)));
}
