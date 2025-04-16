import 'package:dart_geohash/dart_geohash.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'geo_math.dart';
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

//ignore_for_file: avoid_classes_with_only_static_members
class GeohashUtils {

  static String getGeoHashFromLocation({required LatLng location, int precision = 11}) {
    return GeoHasher().encode(location.longitude, location.latitude, precision: precision);
  }

  static LatLng getLocationFromGeoHash({required String geohash}){
    if (geohash.isEmpty){
      throw ArgumentError('Variable geohash must contain at least one symbol');
    }
    return LatLng(GeoHash(geohash).latitude(), GeoHash(geohash).longitude());
  }

  static List<String> getWayGeoHashes({required List<LatLng> points, required int precision}) {
    final Set<String> setOfGeoHashes = {};

    for (final LatLng point in points){
      setOfGeoHashes.add(getGeoHashFromLocation(location: point, precision: precision));
    }
    return setOfGeoHashes.toList();
  }

  ///The function takes vector AB in the format of LatLng coordinates A and B,
  ///along with an additional LatLng coordinate C, and calculates the dot
  ///product between vector AB and point C.
  static double dotProductionByPoints ({required LatLng A, required LatLng B, required LatLng C}){
    final List<double> vectorAB = [B.latitude - A.latitude, B.longitude - A.longitude];
    final List<double> vectorAC = [C.latitude - A.latitude, C.longitude - A.longitude];

    final double dotProduction = vectorAC[0]*vectorAB[0] + vectorAC[1]*vectorAB[1];
    return dotProduction;
  }

  static bool areSidePointsInFrontOfTheRoad ({required List<LatLng> sidePoints, required List<LatLng> wayPoints}){
    if (wayPoints.length < 2){
      throw ArgumentError('Variable wayPoints must contain at least 2 coordinates');
    }

    if (sidePoints.isEmpty){
      return true;
    }

    final Map<LatLng, bool> coordinatesStatus = {};
    for (final LatLng sidePoint in sidePoints){
      coordinatesStatus[sidePoint] = false;
    }

    for (int index = 1; index < wayPoints.length; index++){
      for (final LatLng sidePoint in sidePoints){
        if (GeohashUtils.dotProductionByPoints(A: wayPoints[index - 1], B: wayPoints[index], C: sidePoint) >= 0){
          coordinatesStatus[sidePoint] = true;
        }
      }
    }

    for (final LatLng sidePoint in sidePoints){
      /*
      coordinatesStatus[sidePoint] - the value in the dictionary by key
      coordinatesStatus[sidePoint]! - the value in the dictionary by key, not equal to null
      !coordinatesStatus[sidePoint]! - logical negation of the value in the dictionary, not equal to null
      */
      if (!coordinatesStatus[sidePoint]!){
        return false;
      }
    }

    return true;
  }

  ///Throws an error if there are dots before the starting point of the path.
  static List<LatLng> alignSidePointsV1({required List<LatLng> sidePoints, required List<LatLng> wayPoints}){

    if (!areSidePointsInFrontOfTheRoad(sidePoints: sidePoints, wayPoints: wayPoints)){
      throw ArgumentError('The variable sidePoints contains points located beyond the starting point.');
    }

    final List<(int, LatLng, double)> indexedSidePoints = [];

    for (final LatLng sidePoint in sidePoints){
      //[wayPointIndex, sidePoint, distanceBetween]
      indexedSidePoints.add((0, sidePoint, double.infinity));
    }

    for (int wayPointIndex = 0; wayPointIndex < wayPoints.length; wayPointIndex++){
      for(int i = 0; i < indexedSidePoints.length; i++){
        final (int, LatLng, double) list = indexedSidePoints[i];
        final double distance = GeoMath.getDistance(point1: list.$2, point2: wayPoints[wayPointIndex]);
        if (distance < list.$3){
          indexedSidePoints[i]= (wayPointIndex, list.$2, distance);
        }
      }
    }

    indexedSidePoints.sort((a, b) => a.$1.compareTo(b.$1) != 0 ? a.$1.compareTo(b.$1) : a.$3.compareTo(b.$3));
    final List<LatLng> alignedSidePoints = [];

    for (final (int, LatLng, double) list in indexedSidePoints){
      alignedSidePoints.add(list.$2);
    }

    return alignedSidePoints;
  }
}

