import 'dart:math' as math;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

//ignore_for_file: avoid_classes_with_only_static_members
class GeohashUtils {

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
}