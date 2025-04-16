import 'dart:math' as math;

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
/*
https://github.com/juanxme/google_maps_flutter_platform_interface/blob/master/lib/src/types/location.dart

peace of theory about Earth radius
https://en.wikipedia.org/wiki/Great-circle_distance
 */

//ignore_for_file: avoid_classes_with_only_static_members
class GeoMath {
  static const double earthRadius = 6371009.0; //in meters

  static double getDistance({required LatLng point1, required LatLng point2}) {
    const double earthRadius = GeoMath.earthRadius;

    final double lat1 = point1.latitude;
    final double lon1 = point1.longitude;

    final double lat2 = point2.latitude;
    final double lon2 = point2.longitude;

    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double haversinLat = math.pow(math.sin(dLat / 2), 2).toDouble();
    final double haversinLon = math.pow(math.sin(dLon / 2), 2).toDouble();

    final double a = haversinLat + haversinLon * math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2));
    final double c = 2 * math.asin(math.sqrt(a));

    return earthRadius * c;
  }

  static double _toRadians(double deg) {
    return deg * (math.pi / 180);
  }

  static double _toDegrees(double radians) {
    return (radians * 180) / math.pi;
  }
}



