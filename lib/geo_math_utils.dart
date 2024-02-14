import 'dart:math' as math;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

// Library under development
class GeoMathUtils {

  // in develop
  //checks the perpendicular from a point to a line
  static bool isNearTheEdge({
    required LatLng point, required LatLng startOfSegment, required LatLng endOfSegment, required double desiredPerpendicularLength}) {

    final double perpendicularDistance = desiredPerpendicularLength;

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

  static String convertHashToBase32({required int val}){
    const Map<int, String> dictionary = {0:'0', 1:'1', 2:'2', 3:'3', 4:'4', 5:'5', 6:'6', 7:'7', 8:'8', 9:'9', 10:'b',
      11:'c', 12:'d', 13:'e', 14:'f', 15:'g', 16:'h', 17:'j', 18:'k', 19:'m', 20:'n', 21:'p', 22:'q', 23:'r', 24:'s',
      25:'t', 26:'u', 27:'v', 28:'w', 29:'x', 30:'y', 31:'z'};

    // Ensure the key exists in the dictionary
    if (dictionary.containsKey(val)) {
      return dictionary[val]!; // Non-null assertion operator (!)
    } else {
      return '&';
    }
  }

  static String geoHashForLocation({required LatLng location, required int precision}) {
    if (precision <= 0) {
      throw ArgumentError('precision must be greater than 0');
    } else if (precision > 22) {
      throw ArgumentError('precision cannot be greater than 22');
    }
    Map<String, double> latitudeRange = {'min': -90.0, 'max': 90.0};
    Map<String, double> longitudeRange = {'min': -180.0, 'max': 180.0};
    String hash = '';
    int hashVal = 0;
    int bits = 0;
    bool even = true;
    while (hash.length < precision) {
      double val = even ? location.longitude : location.latitude;
      Map<String, double> range = even ? longitudeRange : latitudeRange;
      double mid = (range['min']! + range['max']!) / 2;

      if (val > mid) {
        hashVal = (hashVal << 1) + 1;
        range['min'] = mid;
      } else {
        hashVal = (hashVal << 1) + 0;
        range['max'] = mid;
      }
      even = !even;
      if (bits < 4) {
        bits++;
      } else {
        bits = 0;
        hash += convertHashToBase32(val: hashVal);
        hashVal = 0;
      }
    }
    return hash;
  }

  static double _toRadians(double deg) {
    return deg * (math.pi / 180);
  }

  static double _toDegrees(double radians) {
    return (radians * 180) / math.pi;
  }

  void boo(){
  }
}