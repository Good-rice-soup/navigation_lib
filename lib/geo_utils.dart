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

/// Get distance between two points.
double getDistance(LatLng p1, LatLng p2) {
  const double earthRadius = earthRadiusInMeters;

  // Преобразование координат в радианы один раз
  final double lat1 = toRadians(p1.latitude);
  final double lon1 = toRadians(p1.longitude);
  final double lat2 = toRadians(p2.latitude);
  final double lon2 = toRadians(p2.longitude);

  final double dLat = lat2 - lat1;
  final double dLon = lon2 - lon1;

  // Вычисление синусов половинных углов через умножение
  final double sinHalfDLat = sin(dLat / 2);
  final double sinHalfDLon = sin(dLon / 2);

  final double haversinLat = sinHalfDLat * sinHalfDLat;
  final double haversinLon = sinHalfDLon * sinHalfDLon;

  // Предварительный расчет косинусов
  final double cosLat1 = cos(lat1);
  final double cosLat2 = cos(lat2);

  final double a = haversinLat + haversinLon * cosLat1 * cosLat2;

  // Обработка возможных ошибок округления: asin не должен превышать 1
  final double sqrtA = sqrt(a);
  final double c = 2 * asin(sqrtA > 1 ? 1 : sqrtA);

  return earthRadius * c;
}

/// Degrees to radians.
double toRadians(double deg) => deg * (pi / 180);

/// Radians to degrees.
double toDegrees(double rad) => rad * (180 / pi);

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
  final double x = (bb * y1 + ab * (x0 - x1) + aa * y0) / denominator;

  return LatLng(x, y);
}

LatLngBounds expandBounds(LatLngBounds bounds, [double expFactor = 1]) {
  final double lat =
      (bounds.northeast.latitude - bounds.southwest.latitude).abs();
  final double lng =
      (bounds.northeast.longitude - bounds.southwest.longitude).abs();
  final LatLng southwest = LatLng(
    bounds.southwest.latitude - (lat * (expFactor - 1) / 2),
    bounds.southwest.longitude - (lng * (expFactor - 1) / 2),
  );
  final LatLng northeast = LatLng(
    bounds.northeast.latitude + (lat * (expFactor - 1) / 2),
    bounds.northeast.longitude + (lng * (expFactor - 1) / 2),
  );

  return LatLngBounds(southwest: southwest, northeast: northeast);
}
