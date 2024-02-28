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
6 	      0.000001 	  individual humans
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

  //int index in list, String 'right' or 'left
  static List<(int, String)> checkPointSideOnWay({required List<LatLng> sidePoints, required List<LatLng> wayPoints}){

    if (sidePoints.isEmpty){
      return [];
    }

    if (wayPoints.length < 2){
      throw ArgumentError('Variable wayPoints must contain at least 2 coordinates');
    }

    //hot patch
    final List<(int, String)> result = [];
    int index = 0;

    for (final LatLng sidePoint in sidePoints){
      double distance = double.infinity;
      LatLng closestPoint = const LatLng(0, 0);

      for (final LatLng wayPoint in wayPoints){
        final double newDistance = GeoMath.getDistance(point1: sidePoint, point2: wayPoint);
        if (newDistance < distance){
          distance = newDistance;
          closestPoint = wayPoint;
        }
      }

      if (closestPoint == wayPoints[wayPoints.length-1]){
        closestPoint = wayPoints[wayPoints.length-2];
      }

      final LatLng pointForRouteVector = wayPoints[GeoMath.getNextRoutePoint(currentLocation: closestPoint, route: wayPoints)];
      final List<double> routeVector = [pointForRouteVector.latitude - closestPoint.latitude, pointForRouteVector.longitude - closestPoint.longitude];
      final List<double> rightPerpendicular = [routeVector[1], -routeVector[0]];
      final List<double> sidePointVector = [sidePoint.latitude - closestPoint.latitude, sidePoint.longitude - closestPoint.longitude];

      final double dotProduction = rightPerpendicular[0]*sidePointVector[0] + rightPerpendicular[1]*sidePointVector[1];

      dotProduction >= 0 ? result.add((index, 'right')) : result.add((index, 'left'));

      index++;
    }
    return result;
  }
}
