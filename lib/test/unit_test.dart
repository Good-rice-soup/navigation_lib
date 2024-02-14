import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import '../geo_math.dart';
import '../geo_math_utils.dart';

//https://planetcalc.ru/73/?ysclid=lrxu6ntrv139316620
//https://planetcalc.ru/1129/?ysclid=lry222bebx102036681
//import '../geo_math_utils.dart';

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
        final double result =
            GeoMath.getDistance(point1: point1, point2: point2);

        expect(result, closeTo(111195.0797343687, 1)); //distance in meters
      });

      test('Test 1.1: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(0, -1);
        final double result =
            GeoMath.getDistance(point1: point1, point2: point2);

        expect(result, closeTo(111195.0797343687, 1));
      });

      test('Test 1.2: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(1, 0);
        final double result =
            GeoMath.getDistance(point1: point1, point2: point2);

        expect(result, closeTo(111195.0797343687, 1));
      });

      test('Test 1.3: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(-1, 0);
        final double result =
            GeoMath.getDistance(point1: point1, point2: point2);

        expect(result, closeTo(111195.0797343687, 1));
      });

      test('Test 1.4: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 0);
        const LatLng point2 = LatLng(0, 0);
        final double result =
            GeoMath.getDistance(point1: point1, point2: point2);

        expect(result, 0.0);
      });

      test('Test 1.5: testing getDistance()', () {
        const LatLng point1 = LatLng(-90, -180);
        const LatLng point2 = LatLng(90, 180);
        final double result =
            GeoMath.getDistance(point1: point1, point2: point2);

        expect(result, closeTo(20015114.352186374, 1));
      });

      test('Test 1.6: testing getDistance()', () {
        const LatLng point1 = LatLng(-60, 100);
        const LatLng point2 = LatLng(80, -90);
        final double result =
            GeoMath.getDistance(point1: point1, point2: point2);

        expect(result, closeTo(17766770.743504174, 1));
      });

      test('Test 1.7: testing getDistance()', () {
        const LatLng point1 = LatLng(0, 180);
        const LatLng point2 = LatLng(0, -180);
        final double result =
            GeoMath.getDistance(point1: point1, point2: point2);

        expect(result, closeTo(0.0000000016, 1));
      });

      test('Test 1.8: testing getDistance()', () {
        const LatLng point1 = LatLng(-90, 0);
        const LatLng point2 = LatLng(90, 0);
        final double result =
            GeoMath.getDistance(point1: point1, point2: point2);

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
        final double result =
            GeoMath.getDistance(point1: point1, point2: point2);

        expect(result, closeTo(1756992.3901310415, 1));
      });

      /*
    [[-1, 42, 15, 0], [1, 74, 18, 42]]
    [[-1, 41, 48, 31], [-1, 124, 22, 49]]
     */
      test('Test 1.10: testing getDistance()', () {
        const LatLng point1 = LatLng(-42.25, 74.31167);
        const LatLng point2 = LatLng(-41.80861, -124.38028);
        final double result =
            GeoMath.getDistance(point1: point1, point2: point2);

        expect(result, closeTo(10482060.482927967, 1));
      });

      /*
    [[-1, 68, 29, 41], [1, 95, 33, 41]]
    [[1, 89, 11, 12], [1, 55, 53, 6]]
     */
      test('Test 1.11: testing getDistance()', () {
        const LatLng point1 = LatLng(-68.49472, 95.56139);
        const LatLng point2 = LatLng(89.18667, 55.885);
        final double result =
            GeoMath.getDistance(point1: point1, point2: point2);

        expect(result, closeTo(17553580.84593416, 1));
      });
    });

    group('Testing isPointOnPolyline()', () {
      test('Test 2.0: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0, 0);
        const double radius = GeoMath.earthRadius;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 2.0: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0, 0);
        const double radius = 1;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      /*
      111134.861111 meters in one degree
      1852.24768519 meters in one minute
      30.8707947531 meters in one second
      */
      test('Test 2.0: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(1, 0);
        const double radius = GeoMath.earthRadius;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 2.1: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(1, 0);
        const double radius = 1000000;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 2.2: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(1, 0);
        const double radius = 100000;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, false);
      });

      test('Test 2.3: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0.016, 0);
        const double radius = 100000;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 2.4: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0.016, 0);
        const double radius = 10000;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 2.5: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0.016, 0);
        const double radius = 1000;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, false);
      });

      test('Test 2.6: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0.00027, 0);
        const double radius = 1000;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 2.7: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0.00027, 0);
        const double radius = 100;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 2.8: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0.00027, 0);
        const double radius = 10;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, false);
      });

      test('Test 2.9: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0.00005, 0);
        const double radius = 10;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 2.10: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0.00005, 0);
        const double radius = 2;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, false);
      });

      test('Test 2.11: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0.000001, 0);
        const double radius = 1.5;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      // An approximate 60-meter error introduced due to the Earth's non-spherical shape.
      test('Test 2.12: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0, 9);
        const double radius = 111200;
        const List<LatLng> polyline = [
          LatLng(8, -4),
          LatLng(-3, 1),
          LatLng(0, 10),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 2.13: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(-3.5, 0.5);
        const double radius = 111135;
        const List<LatLng> polyline = [
          LatLng(8, -4),
          LatLng(-3, 1),
          LatLng(0, 10),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 2.14: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(4, 2);
        const double radius = 111135;
        const List<LatLng> polyline = [
          LatLng(8, -4),
          LatLng(-3, 1),
          LatLng(0, 10),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, false);
      });

      test('Test 2.15: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(40.7128, -74.0060);
        const double radius = GeoMath.earthRadius;
        const List<LatLng> polyline = [
          LatLng(40.7128, -74.0060),
          LatLng(34.0522, -118.2437),
          LatLng(41.8781, -87.6298),
        ];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 2.15: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(40.7128, -74.0060);
        const double radius = GeoMath.earthRadius;
        const List<LatLng> polyline = [];

        final bool result = GeoMath.isPointOnPolyline(
            point: point, polyline: polyline, desiredRadius: radius);

        expect(result, false);
      });

      test('Test 2.15: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(40.7128, -74.0060);
        const double radius = -100;
        const List<LatLng> polyline = [
          LatLng(40.7128, -74.0060),
          LatLng(34.0522, -118.2437),
          LatLng(41.8781, -87.6298),
        ];

        expect(
            () => GeoMath.isPointOnPolyline(
                point: point, polyline: polyline, desiredRadius: radius),
            throwsArgumentError);
      });
    });

    group('Testing getNextRoutePoint()', () {
      test('Test 3.0: testing getNextRoutePoint()', () {
        const LatLng currentLocation = LatLng(40.7128, -74.0060);
        const List<LatLng> route = [
          LatLng(40.7128, -74.0060),
          LatLng(34.0522, -118.2437),
          LatLng(41.8781, -87.6298),
        ];

        final LatLng nextPoint = GeoMath.getNextRoutePoint(
            currentLocation: currentLocation, route: route);

        expect(nextPoint, const LatLng(41.8781, -87.6298));
      });

      test('Test 3.1: testing getNextRoutePoint()', () {
        const LatLng currentLocation = LatLng(0, 0);
        const List<LatLng> route = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(1, 1),
        ];

        final LatLng nextPoint = GeoMath.getNextRoutePoint(
            currentLocation: currentLocation, route: route);

        expect(nextPoint, const LatLng(0, 1));
      });

      test('Test 3.2: testing getNextRoutePoint()', () {
        const LatLng currentLocation = LatLng(-1, 0);
        const List<LatLng> route = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(1, 1),
        ];

        final LatLng nextPoint = GeoMath.getNextRoutePoint(
            currentLocation: currentLocation, route: route);

        expect(nextPoint, const LatLng(0, 0));
      });

      test('Test 3.3: testing getNextRoutePoint()', () {
        const LatLng currentLocation = LatLng(-1, 0);
        const List<LatLng> route = [];

        expect(
            () => GeoMath.getNextRoutePoint(
                currentLocation: currentLocation, route: route),
            throwsArgumentError);
      });
    });

    group('Testing getDistanceToNextPoint()', () {
      test('Test 4.0: testing getDistanceToNextPoint()', () {
        const LatLng currentLocation = LatLng(40.7128, -74.0060);
        const List<LatLng> route = [
          LatLng(40.7128, -74.0060),
          LatLng(34.0522, -118.2437),
          LatLng(41.8781, -87.6298),
        ];

        final double distanceToNextPoint = GeoMath.getDistanceToNextPoint(
            currentLocation: currentLocation, route: route);

        expect(distanceToNextPoint,
            closeTo(GeoMath.getDistance(point1: const LatLng(40.7128, -74.0060), point2: const LatLng(41.8781, -87.6298)), 1));
      });
    });

    group('Testing getRouteCorners()', () {
      test('Test 5.0: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [];

        final LatLngBounds bounds =
            GeoMath.getRouteCorners(listOfRoutes: routes);

        expect(
            bounds,
            equals(LatLngBounds(
                southwest: const LatLng(0, 0), northeast: const LatLng(0, 0))));
      });

      test('Test 5.1: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [[], []];

        final LatLngBounds bounds =
            GeoMath.getRouteCorners(listOfRoutes: routes);

        expect(
            bounds,
            equals(LatLngBounds(
                southwest: const LatLng(0, 0), northeast: const LatLng(0, 0))));
      });

      test('Test 5.2: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [
          [LatLng(1.0, 2.0), LatLng(3.0, 4.0), LatLng(5.0, 6.0)],
          []
        ];

        final LatLngBounds bounds =
            GeoMath.getRouteCorners(listOfRoutes: routes);

        expect(
            bounds,
            equals(LatLngBounds(
                southwest: const LatLng(0, 0), northeast: const LatLng(0, 0))));
      });

      test('Test 5.3: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [
          [LatLng(1.0, 2.0), LatLng(3.0, 4.0), LatLng(5.0, 6.0)]
        ];

        final LatLngBounds bounds =
            GeoMath.getRouteCorners(listOfRoutes: routes);

        expect(
            bounds,
            equals(LatLngBounds(
                southwest: const LatLng(1, 2), northeast: const LatLng(5, 6))));
      });

      test('Test 5.4: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [
          [LatLng(1.0, 2.0), LatLng(3.0, 4.0)],
          [LatLng(-1.0, -2.0), LatLng(-3.0, -4.0)]
        ];

        final LatLngBounds bounds =
            GeoMath.getRouteCorners(listOfRoutes: routes);

        expect(
            bounds,
            equals(LatLngBounds(
                southwest: const LatLng(-3, -4),
                northeast: const LatLng(3, 4))));
      });
    });

    group('Testing calculateAzimuth()', () {
      test('Test 6.0: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(0, 0);
        const LatLng nextPoint = LatLng(0, 1);

        final double result = GeoMath.calculateAzimuth(
            currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(90.0, 0.1));
      });

      test('Test 6.1: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(0, 0);
        const LatLng nextPoint = LatLng(1, 0);

        final double result = GeoMath.calculateAzimuth(
            currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(0.0, 0.1));
      });

      test('Test 6.2: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(0, 0);
        const LatLng nextPoint = LatLng(0, -1);

        final double result = GeoMath.calculateAzimuth(
            currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(270.0, 0.1));
      });

      test('Test 6.3: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(-1, 3);
        const LatLng nextPoint = LatLng(6, -19);

        final double result = GeoMath.calculateAzimuth(
            currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(287.8382, 0.1));
      });

      test('Test 6.4: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(-1, 3);
        const LatLng nextPoint = LatLng(-1.00001, 3.00001);

        final double result = GeoMath.calculateAzimuth(
            currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(134.912, 0.1));
      });
    });
  });

  group('Test geo_math_utils library', () {

    group('Testing convertHashToBase32()', () {
      test('Test 0.0: testing geoHashForLocation()', () {
        final String result = GeoMathUtils.convertHashToBase32(val: 1);
        expect(result, '1');
      });
    });

    group('Testing geoHashForLocation()', () {
      test('Test 0.0: testing geoHashForLocation()', () {
        final String result = GeoMathUtils.geoHashForLocation(location: const LatLng(57.64911, 10.40744), precision: 11);
        expect(result, 'u4pruydqqvj');
      });
    });

  /*
    // in develop
    group('Testing isNearTheEdge()', () {
      test('Test 0.0: testing isNearTheEdge()', () {
        const LatLng point = LatLng(0.5, 0);
        const LatLng startOfSegment = LatLng(0, 0);
        const LatLng endOfSegment = LatLng(1, 0);
        const double perpendicularLength = 1000000;

        final bool result = GeoMathUtils.isNearTheEdge(
            point: point,
            startOfSegment: startOfSegment,
            endOfSegment: endOfSegment,
            desiredPerpendicularLength: perpendicularLength);

        expect(result, true);
      });
    });
    */
  });
}
