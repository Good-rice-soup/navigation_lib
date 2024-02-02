import 'dart:math' as math;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

class GeoMathUtils {

  // in develop
  //checks the perpendicular from a point to a line
  static bool isNearTheEdge({
    required LatLng point,
    required LatLng startOfSegment,
    required LatLng endOfSegment,
    required double desiredPerpendicularLength}) {

    double perpendicularDistance = desiredPerpendicularLength;

    // Geographic coordinates of vector
    final double phiA = _toRadians(startOfSegment.latitude);
    final double thetaA = _toRadians(startOfSegment.longitude);
    final double phiB = _toRadians(endOfSegment.latitude);
    final double thetaB = _toRadians(endOfSegment.longitude);

    //transforming a vector into Cartesian coordinate system
    final double xBA = (math.sin(phiA) * math.cos(thetaA)) - (math.sin(phiB) * math.cos(thetaB));
    final double yBA = (math.sin(phiA) * math.sin(thetaA)) - (math.sin(phiB) * math.sin(thetaB));
    final double zBA = math.cos(phiA) - math.cos(phiB);

    //Rotating vector BA 90 degrees counterclockwise to obtain vector AC
    double xAC = -yBA;
    double yAC = xBA;
    double zAC = zBA;

    //Rotating vector BA 90 degrees clockwise to obtain vector BD
    double xBD = yBA;
    double yBD = -xBA;
    double zBD = zBA;

    final double lengthAC = math.sqrt((xAC * xAC) + (yAC * yAC) + (zAC * zAC));
    final double lengthBD = math.sqrt((xBD * xBD) + (yBD * yBD) + (zBD * zBD));

    final double scaleAC = perpendicularDistance / lengthAC;
    final double scaleBD = perpendicularDistance / lengthBD;

    xAC = xAC * scaleAC;
    yAC = yAC * scaleAC;
    zAC = zAC * scaleAC;

    xBD = xBD * scaleBD;
    yBD = yBD * scaleBD;
    zBD = zBD * scaleBD;

    //The determination of the geographic coordinates of points C and D
    final LatLng C = LatLng(_toDegrees(math.asin(zAC)), _toDegrees(math.atan2(yAC, xAC)));
    final LatLng D = LatLng(_toDegrees(math.asin(zBD)), _toDegrees(math.atan2(yBD, xBD)));

    final bool isLatitudeBetween = (C.latitude <= point.latitude && point.latitude <= D.latitude) ||
        (D.latitude <= point.latitude && point.latitude <= C.latitude);

    final bool isLongitudeBetween = (C.longitude <= point.longitude && point.longitude <= D.longitude) ||
        (D.longitude <= point.longitude && point.longitude <= C.longitude);

    return isLatitudeBetween && isLongitudeBetween;
  }

  static double _toRadians(double deg) {
    return deg * (math.pi / 180);
  }

  static double _toDegrees(double radians) {
    return (radians * 180) / math.pi;
  }

  void boo(){
    int a;
  }
}