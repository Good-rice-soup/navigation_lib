import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import '../geo_math.dart';
//https://planetcalc.ru/73/?ysclid=lrxu6ntrv139316620
//https://planetcalc.ru/1129/?ysclid=lry222bebx102036681
import '../geo_math_utils.dart';

void main() {
  group('Test geo_math library', () {

    group('Testing LatLon class', () {
      /*
    This class accepts latitude values from -90 to 90 and longitude values from -180 to 180.
    When inputting values beyond these ranges, it behaves like a periodic function (for example, sine)
    and wraps values from one to another. For example, LatLon(90.0, 0.0) == LatLon(90.0, 360.0).
    However, this behavior applies only to longitude. Latitude values are not wrapped and are strictly fixed.
    */
      test('Test 1.0: testing LatLon class', () {
        const LatLng result = LatLng(1000, -380);
        expect(result,  const LatLng(90, -20));
      });
    });

    group('Testing getDistance()', () {
      test('Test 2.0: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(0, 1);
        final double result = GeoMath.getDistance(point1: point1, point2: point2);

        expect(result,  closeTo(111195.0797343687, 1));//distance in meters
      });

      test('Test 2.1: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(0, -1);
        final double result = GeoMath.getDistance(point1: point1, point2: point2);

        expect(result,  closeTo(111195.0797343687, 1));
      });

      test('Test 2.2: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(1, 0);
        final double result = GeoMath.getDistance(point1: point1, point2: point2);

        expect(result,  closeTo(111195.0797343687, 1));
      });

      test('Test 2.3: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(-1, 0);
        final double result = GeoMath.getDistance(point1: point1, point2: point2);

        expect(result,  closeTo(111195.0797343687, 1));
      });

      test('Test 2.4: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(0, 0);
        final double result = GeoMath.getDistance(point1: point1, point2: point2);

        expect(result,  0.0);
      });

      test('Test 2.5: testing getDistance()', () {
        const LatLng point1 = LatLng(-90, -180);
        const LatLng point2 = LatLng(90, 180);
        final double result = GeoMath.getDistance(point1: point1, point2: point2);

        expect(result,  closeTo(20015114.352186374, 1));
      });

      test('Test 2.6: testing getDistance()', () {
        const LatLng point1 = LatLng(-60, 100);
        const LatLng point2 = LatLng(80, -90);
        final double result = GeoMath.getDistance(point1: point1, point2: point2);

        expect(result,  closeTo(17766770.743504174, 1));
      });

      test('Test 2.7: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 180);
        const LatLng point2 = LatLng(0, -180);
        final double result = GeoMath.getDistance(point1: point1, point2: point2);

        expect(result,  closeTo(0.0000000016, 1));
      });

      test('Test 2.8: testing getDistance()', () {
        const LatLng point1 = LatLng(-90, 0);
        const LatLng point2 = LatLng(90, 0);
        final double result = GeoMath.getDistance(point1: point1, point2: point2);

        expect(result,  closeTo(20015114.352186374, 1));
      });

      /*
    [[1, 83, 40, 19], [-1, 103, 38, 29]]
    [[1, 79, 34, 0], [1, 36, 13, 38]]
    B[0] *( B[1] + (1 / 60 * B[2]) + (1 / 3600 * B[3]))
    */
      test('Test 2.9: testing getDistance()', () {
        const LatLng point1 = LatLng(83.67194, -103.64139);
        const LatLng point2 = LatLng(79.56667, 36.22722);
        final double result = GeoMath.getDistance(point1: point1, point2: point2);

        expect(result,  closeTo(1756992.3901310415, 1));
      });

      /*
    [[-1, 42, 15, 0], [1, 74, 18, 42]]
    [[-1, 41, 48, 31], [-1, 124, 22, 49]]
     */
      test('Test 2.10: testing getDistance()', () {
        const LatLng point1 = LatLng(-42.25, 74.31167);
        const LatLng point2 = LatLng(-41.80861, -124.38028);
        final double result = GeoMath.getDistance(point1: point1, point2: point2);

        expect(result,  closeTo(10482060.482927967, 1));
      });

      /*
    [[-1, 68, 29, 41], [1, 95, 33, 41]]
    [[1, 89, 11, 12], [1, 55, 53, 6]]
     */
      test('Test 2.11: testing getDistance()', () {
        const LatLng point1 = LatLng(-68.49472, 95.56139);
        const LatLng point2 = LatLng(89.18667, 55.885);
        final double result = GeoMath.getDistance(point1: point1, point2: point2);

        expect(result,  closeTo(17553580.84593416, 1));
      });
    });

    /*
    // in develop
    group('Testing isPointOnPolyline()', () {
      test('Test 3.0: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(40.7128, -74.0060);
        const List<LatLng> polyline = [
          LatLng(40.7128, -74.0060),
          LatLng(34.0522, -118.2437),
          LatLng(41.8781, -87.6298),
        ];

        final bool result = GeoMath.isPointOnPolyline(point: point, polyline: polyline, desiredRadius: 6371000.0);

        expect(result, true);
      });
    });

    // in develop
    group('Testing getNextRoutePoint()', () {
      test('Test4.0: testing getNextRoutePoint()', () {
        const LatLng currentLocation = LatLng(40.7128, -74.0060); // Нью-Йорк
        final List<LatLng> route = [
          LatLng(40.7128, -74.0060),
          LatLng(34.0522, -118.2437),
          LatLng(41.8781, -87.6298),
        ];

        final LatLng nextPoint = GeoMath.getNextRoutePoint(currentLocation: currentLocation, route: route);

        expect(nextPoint, equals(LatLng(34.0522, -118.2437)));
      });
    });

    // in develop
    group('Testing getDistanceToNextPoint()', () {
      test('Test 5.0: testing getDistanceToNextPoint()', () {
        const LatLng currentLocation = LatLng(40.7128, -74.0060); // Нью-Йорк
        final List<LatLng> route = [
          LatLng(40.7128, -74.0060),
          LatLng(34.0522, -118.2437),
          LatLng(41.8781, -87.6298),
        ];

        final double distanceToNextPoint = GeoMath.getDistanceToNextPoint(currentLocation: currentLocation, route: route);

        // Проверяем, что расстояние близко к ожидаемому
        expect(distanceToNextPoint, closeTo(3939405.864, 1.0)); // 1.0 - погрешность в метрах
      });
    });
     */

    group('Testing getRouteCorners()', () {
      test('Test 6.0: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [];

        final List<LatLng> bounds = GeoMath.getRouteCorners(listOfRoutes: routes);

        expect(bounds, equals([]));
      });

      test('Test 6.1: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [[], []];

        final List<LatLng> bounds = GeoMath.getRouteCorners(listOfRoutes: routes);

        expect(bounds, equals([]));
      });

      test('Test 6.2: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [
          [LatLng(1.0, 2.0), LatLng(3.0, 4.0), LatLng(5.0, 6.0)],
          []
        ];

        final List<LatLng> bounds = GeoMath.getRouteCorners(listOfRoutes: routes);

        expect(bounds, equals([]));
      });

      test('Test 6.3: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [
          [LatLng(1.0, 2.0), LatLng(3.0, 4.0), LatLng(5.0, 6.0)]
        ];

        final List<LatLng> bounds = GeoMath.getRouteCorners(listOfRoutes: routes);

        expect([bounds[0].latitude, bounds[0].longitude, bounds[1].latitude, bounds[1].longitude], equals([1.0, 2.0, 5.0, 6.0]));
      });

      test('Test 6.4: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [
          [LatLng(1.0, 2.0), LatLng(3.0, 4.0)],
          [LatLng(-1.0, -2.0), LatLng(-3.0, -4.0)]
        ];

        final List<LatLng> bounds = GeoMath.getRouteCorners(listOfRoutes: routes);

        expect([bounds[0].latitude, bounds[0].longitude,bounds[1].latitude, bounds[1].longitude], equals([-3.0, -4.0, 3.0, 4.0]));
      });
    });

    group('Testing calculateAzimuth()', () {
      test('Test 7.0: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(0, 0);
        const LatLng nextPoint = LatLng(0, 1);

        final double result = GeoMath.calculateAzimuth(currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(90.0, 0.1));
      });

      test('Test 7.1: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(0, 0);
        const LatLng nextPoint = LatLng(1, 0);

        final double result = GeoMath.calculateAzimuth(currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(0.0, 0.1));
      });

      test('Test 7.2: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(0, 0);
        const LatLng nextPoint = LatLng(0, -1);

        final double result = GeoMath.calculateAzimuth(currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(270.0, 0.1));
      });
    });
  });

  /*
  group('Test geo_math_utils library', () {
    // in develop
    group('Testing isNearTheEdge()', () {
      test('Test 0.0: testing isNearTheEdge()', () {
        const LatLng point = LatLng(40.7128, -74.0060);
        const LatLng startOfSegment = LatLng(40.7128, -74.0060);
        const LatLng endOfSegment = LatLng(34.0522, -118.2437);
        const double perpendicularLength = GeoMath.earthRadius;

        final bool result = GeoMathUtils.isNearTheEdge(
            point: point, startOfSegment: startOfSegment, endOfSegment: endOfSegment, desiredPerpendicularLength: perpendicularLength);

        expect(result, true);
      });
    });
  });
   */
}
