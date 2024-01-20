import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import '../geo_math.dart';

void main() {
  group('Test geo match distance', () {
    test('Test1', () {
      final result = GeoMath.getDistance(
          point1: const LatLng(1, 1), point2: const LatLng(2, 2));
      expect(result, 100);
    });

    test('Test2', () {
      final result = GeoMath.getDistance(
          point1: const LatLng(3, 4), point2: const LatLng(4, 5));
      expect(result, 100);
    });
  });
}
