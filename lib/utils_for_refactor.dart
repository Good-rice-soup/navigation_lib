import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart' as gm;
import 'package:latlong2/latlong.dart';

import 'geohash_base.dart';

//ignore_for_file: avoid_classes_with_only_static_members
class GeoMathUtils{
  static List<String> getWayGeohashes({required List<LatLng> points, required int precision}) {
    final Set<String> geohashes = {};

    for (int i = 0; i < points.length - 1; i++) {
      final LatLng start =LatLng( points[i].latitude, points[i].longitude); ;

      final LatLng end = LatLng(points[i + 1].latitude, points[i + 1].longitude);
      //final LatLng end = points[i + 1];

      // Добавляем геохеш начальной точки
      geohashes.add(Geohash.encode(start.latitude, start.longitude, codeLength: precision));

      final double distance = const Distance().as(LengthUnit.Meter, start, end);
      /*
      final double step = Geohash.distance(precision); // Расстояние, соответствующее одной плитке геохеша на этой точности
      */

      //TODO
      const double step = 5000;
      for (double d = step; d < distance; d += step) {
        final LatLng intermediate = const Distance().offset(start, d, const Distance().bearing(start, end));
        geohashes.add(Geohash.encode(intermediate.latitude, intermediate.longitude, codeLength: precision));
      }

      // Добавляем геохеш конечной точки
      geohashes.add(Geohash.encode(end.latitude, end.longitude, codeLength: precision));
    }

    return geohashes.toList();
  }

}
