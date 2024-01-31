import 'dart:math' as math;

import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
//https://github.com/juanxme/google_maps_flutter_platform_interface/blob/master/lib/src/types/location.dart

//peace of theory about Earth radius
//https://en.wikipedia.org/wiki/Great-circle_distance

class GeoMath {
  static const double earthRadius = 6371009.0; //in meters

  static double get _radiusOfEarth => earthRadius;

  static double getDistance({required LatLng point1, required LatLng point2}) {
    final double earthRadius = GeoMath._radiusOfEarth;

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

  // in develop
  //checks the perpendicular from a point to a line
  static bool isNearTheEdge(
      {required LatLng point, required LatLng startOfSegment, required LatLng endOfSegment, required double perpendicularLength}) {
    double desiredDistance = perpendicularLength;

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

    final double scaleAC = desiredDistance / lengthAC;
    final double scaleBD = desiredDistance / lengthBD;

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

  // in develop
  static bool isPointOnPolyline(
      {required LatLng point, required List<LatLng> polyline, required double radius}) {

    if (polyline.isEmpty){
      return false;
    }

    if (radius.isNaN || radius.isNegative) {
      throw ArgumentError("Variable radius can't be NaN or negative");
    }

    //checking points on a polyline
    double minDistance = double.infinity;
    for (LatLng polylinePoint in  polyline) {
      double distance = getDistance(point1: point, point2: polylinePoint);

      if (distance < minDistance){
        minDistance = distance;
      }

      if (minDistance < radius){
        return true;
      }
    }

    //polyline edges check
    for (int i = 0; i < (polyline.length - 1); i++){
      LatLng startOfSegment = polyline[i];
      LatLng endOfSegment = polyline[i+1];

      if (isNearTheEdge(point: point, startOfSegment: startOfSegment, endOfSegment: endOfSegment, perpendicularLength: radius)){
        return true;
      }
    }

    return false;
  }

  // in develop
  static LatLng getNextRoutePoint(
      {required LatLng currentLocation, required List<LatLng> route}) {

    if (route.isEmpty) {
      throw ArgumentError("Variable route can't be empty");
    }

    double minDistance = double.infinity;
    int nextPointIndex = 0;

    for (int i = 0; i < route.length; i++){
      double distance = getDistance(point1: currentLocation, point2: route[i]);

      if (distance < minDistance){
        minDistance = distance;
        nextPointIndex = i;
      }
    }
    
    return route[nextPointIndex];
  }

  // in develop
  static double getDistanceToNextPoint(
      {required LatLng currentLocation, required List<LatLng> route}) {
    final LatLng nextPoint = getNextRoutePoint(currentLocation: currentLocation, route: route);

    return getDistance(point1: currentLocation, point2: nextPoint);
  }

  static List<LatLng> getRouteCorners({required List<List<LatLng>> listOfRoutes}){

    if (listOfRoutes.isEmpty || listOfRoutes.any((route) => route.isEmpty)) {
      return [];
    }

    double minLatitude = double.infinity;
    double maxLatitude = -double.infinity;
    double minLongitude = double.infinity;
    double maxLongitude = -double.infinity;

    for (List<LatLng> route in listOfRoutes) {
      for (LatLng coordinate in route) {
        minLatitude = coordinate.latitude < minLatitude ? coordinate.latitude : minLatitude;
        maxLatitude = coordinate.latitude > maxLatitude ? coordinate.latitude : maxLatitude;
        minLongitude = coordinate.longitude < minLongitude ? coordinate.longitude : minLongitude;
        maxLongitude = coordinate.longitude > maxLongitude ? coordinate.longitude : maxLongitude;

      }
    }
    
    final LatLng maxCoordinate = LatLng(maxLatitude, maxLongitude);
    final LatLng minCoordinate = LatLng(minLatitude, minLongitude);

    return [minCoordinate, maxCoordinate];
  }

  static double _toRadians(double deg) {
    return deg * (math.pi / 180);
  }

  static double _toDegrees(double radians) {
    return (radians * 180) / math.pi;
  }

  //It exists only for the balance of good and evil, nothing more
  void boo(){
    int a;
  }
}


