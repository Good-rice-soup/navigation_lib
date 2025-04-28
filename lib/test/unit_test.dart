import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import '../navigation_lib.dart';

//https://planetcalc.ru/73/?ysclid=lrxu6ntrv139316620
//https://planetcalc.ru/1129/?ysclid=lry222bebx102036681

void main() {
  group('Test geo_math library', () {
    group('Testing LatLon class', () {
      /*
    This class accepts latitude values from -90 to 90 and longitude values from -180 to 180.
    When inputting values beyond these ranges, it behaves like a periodic function (for example, sine)
    and wraps values from one to another. For example, LatLon(90.0, 0.0) == LatLon(90.0, 360.0).
    However, this behavior applies only to longitude. Latitude values are not wrapped and are strictly fixed.
    */
      test('Test 0.0: testing LatLon class', () {
        const LatLng result = LatLng(1000, -380);
        expect(result, const LatLng(90, -20));
      });
    });

    group('Testing getDistance()', () {
      test('Test 1.0: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(0, 1);
        final double result = getDistance(p1: point1, p2: point2);

        expect(result, closeTo(111195.0797343687, 1)); //distance in meters
      });

      test('Test 1.1: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(0, -1);
        final double result = getDistance(p1: point1, p2: point2);

        expect(result, closeTo(111195.0797343687, 1));
      });

      test('Test 1.2: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(1, 0);
        final double result = getDistance(p1: point1, p2: point2);

        expect(result, closeTo(111195.0797343687, 1));
      });

      test('Test 1.3: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(-1, 0);
        final double result = getDistance(p1: point1, p2: point2);

        expect(result, closeTo(111195.0797343687, 1));
      });

      test('Test 1.4: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(0, 0);
        final double result = getDistance(p1: point1, p2: point2);

        expect(result, 0.0);
      });

      test('Test 1.5: testing getDistance()', () {
        const LatLng point1 = LatLng(-90, -180);
        const LatLng point2 = LatLng(90, 180);
        final double result = getDistance(p1: point1, p2: point2);

        expect(result, closeTo(20015114.352186374, 1));
      });

      test('Test 1.6: testing getDistance()', () {
        const LatLng point1 = LatLng(-60, 100);
        const LatLng point2 = LatLng(80, -90);
        final double result = getDistance(p1: point1, p2: point2);

        expect(result, closeTo(17766770.743504174, 1));
      });

      test('Test 1.7: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 180);
        const LatLng point2 = LatLng(0, -180);
        final double result = getDistance(p1: point1, p2: point2);

        expect(result, closeTo(0.0000000016, 1));
      });

      test('Test 1.8: testing getDistance()', () {
        const LatLng point1 = LatLng(-90, 0);
        const LatLng point2 = LatLng(90, 0);
        final double result = getDistance(p1: point1, p2: point2);

        expect(result, closeTo(20015114.352186374, 1));
      });

      /*
    [[1, 83, 40, 19], [-1, 103, 38, 29]]
    [[1, 79, 34, 0], [1, 36, 13, 38]]
    B[0] *( B[1] + (1 / 60 * B[2]) + (1 / 3600 * B[3]))
    */
      test('Test 1.9: testing getDistance()', () {
        const LatLng point1 = LatLng(83.67194, -103.64139);
        const LatLng point2 = LatLng(79.56667, 36.22722);
        final double result = getDistance(p1: point1, p2: point2);

        expect(result, closeTo(1756992.3901310415, 1));
      });

      /*
    [[-1, 42, 15, 0], [1, 74, 18, 42]]
    [[-1, 41, 48, 31], [-1, 124, 22, 49]]
     */
      test('Test 1.10: testing getDistance()', () {
        const LatLng point1 = LatLng(-42.25, 74.31167);
        const LatLng point2 = LatLng(-41.80861, -124.38028);
        final double result = getDistance(p1: point1, p2: point2);

        expect(result, closeTo(10482060.482927967, 1));
      });

      /*
    [[-1, 68, 29, 41], [1, 95, 33, 41]]
    [[1, 89, 11, 12], [1, 55, 53, 6]]
     */
      test('Test 1.11: testing getDistance()', () {
        const LatLng point1 = LatLng(-68.49472, 95.56139);
        const LatLng point2 = LatLng(89.18667, 55.885);
        final double result = getDistance(p1: point1, p2: point2);

        expect(result, closeTo(17553580.84593416, 1));
      });
    });
  });
}
