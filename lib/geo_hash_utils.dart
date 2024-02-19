import 'package:dart_geohash/dart_geohash.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

//ignore_for_file: avoid_classes_with_only_static_members
class GeohashUtils {
  /*
  not used

  static String convertHashToBase32({required int val}) {
    const Map<int, String> dictionary = {
      0: '0', 1: '1', 2: '2', 3: '3', 4: '4', 5: '5', 6: '6', 7: '7', 8: '8', 9: '9', 10: 'b', 11: 'c', 12: 'd',
      13: 'e', 14: 'f', 15: 'g', 16: 'h', 17: 'j', 18: 'k', 19: 'm', 20: 'n', 21: 'p', 22: 'q', 23: 'r', 24: 's',
      25: 't', 26: 'u', 27: 'v', 28: 'w', 29: 'x', 30: 'y', 31: 'z'
    };

    // Ensure the key exists in the dictionary
    if (dictionary.containsKey(val)) {
      return dictionary[val]!; // Non-null assertion operator (!)
    } else {
      return '&';
    }
  }
   */

  static String getGeoHashFromLocation({required LatLng location, int precision = 11}) {
    /*
    wrong, try again

    //static String geoHashFromLocation({required LatLng location, int precision = 11})

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
     */
    return GeoHasher().encode(location.longitude, location.latitude, precision: precision);
  }

  /*
  not used

  static int convertHashFromBase32({required String val}) {
    const Map<String, int> dictionary = {
      '0': 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9, 'b': 10, 'c': 11, 'd': 12,
      'e': 13, 'f': 14, 'g': 15, 'h': 16, 'j': 17, 'k': 18, 'm': 19, 'n': 20, 'p': 21, 'q': 22, 'r': 23, 's': 24,
      't': 25, 'u': 26, 'v': 27, 'w': 28, 'x': 29, 'y': 30, 'z': 31
    };

    // Ensure the key exists in the dictionary
    if (dictionary.containsKey(val)) {
      return dictionary[val]!; // Non-null assertion operator (!)
    } else {
      return -1;
    }
  }

  static double _decode ({required Map<String, double> coordinatesRange, required String binaryString}){
    for (int i = 0; i < binaryString.length; i++){
      double mid  = (coordinatesRange['min']! + coordinatesRange['max']!) / 2;

      if (binaryString[i] == '1'){
        coordinatesRange['min'] = mid;
      } else {
        coordinatesRange['max'] = mid;
      }
    }

    return (coordinatesRange['min']! + coordinatesRange['max']!) / 2;
}
   */

  static LatLng getLocationFromGeoHash({required String geohash}){
    /*
    wrong, try again

    List<int> decimalGeohash = [];
    for(int i = 0; i < geohash.length; i++){
      decimalGeohash.add(convertHashFromBase32(val: geohash[i]));
    }

    List<String> binaryGeohash = [];
    for (int digit in decimalGeohash){
      binaryGeohash.add(digit.toRadixString(2));
    }

    final String binaryString = binaryGeohash.join();
    String binaryLatitude = '';
    String binaryLongitude = '';

    for (int i = 0; i < binaryString.length; i++){
      if(int.parse(binaryString[i]).isEven){
        binaryLatitude += binaryString[i];
      } else {
        binaryLongitude += binaryString[i];
      }
    }

    Map<String, double> latitudeRange = {'min': -90.0, 'max': 90.0};
    Map<String, double> longitudeRange = {'min': -180.0, 'max': 180.0};
    double latitude = _decode(coordinatesRange: latitudeRange, binaryString: binaryLatitude);
    double longitude = _decode(coordinatesRange: longitudeRange, binaryString: binaryLongitude);
     */
    return LatLng(GeoHash(geohash).latitude(), GeoHash(geohash).longitude());
  }

  static List<String> getWayGeoHashes({required List<LatLng> points, required int precision}) {
    final Set<String> setOfGeoHashes = {};

    for (final LatLng point in points){
      setOfGeoHashes.add(getGeoHashFromLocation(location: point, precision: precision));
    }
    return setOfGeoHashes.toList();
  }

  //int index in list, String 'right' or 'left
  //which size geo hashes are?
  List<(int, String)> checkPointSideOnWay({required List<LatLng> points, required List<LatLng> wayPoints}){
    return [];
  }
}
