import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import '../geo_hash_utils.dart';
import '../geo_math.dart';

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
      test('Test 3.0: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0, 0);
        const double radius = GeoMath.earthRadius;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 3.1: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(0, 0);
        const double radius = 1;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      /*
      111134.861111 meters in one degree
      1852.24768519 meters in one minute
      30.8707947531 meters in one second
      */
      test('Test 3.2: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(1, 0);
        const double radius = GeoMath.earthRadius;
        const List<LatLng> polyline = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(0, 2),
        ];

        final bool result = GeoMath.isPointOnPolyline(point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 3.3: testing isPointOnPolyline()', () {
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

      test('Test 3.4: testing isPointOnPolyline()', () {
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

      test('Test 3.5: testing isPointOnPolyline()', () {
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

      test('Test 3.6: testing isPointOnPolyline()', () {
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

      test('Test 3.7: testing isPointOnPolyline()', () {
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

      test('Test 3.8: testing isPointOnPolyline()', () {
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

      test('Test 3.9: testing isPointOnPolyline()', () {
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

      test('Test 3.10: testing isPointOnPolyline()', () {
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

      test('Test 3.11: testing isPointOnPolyline()', () {
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

      test('Test 3.12: testing isPointOnPolyline()', () {
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

      test('Test 3.13: testing isPointOnPolyline()', () {
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
      test('Test 3.14: testing isPointOnPolyline()', () {
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

      test('Test 3.15: testing isPointOnPolyline()', () {
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

      test('Test 3.16: testing isPointOnPolyline()', () {
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

      test('Test 3.17: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(40.7128, -74.0060);
        const double radius = GeoMath.earthRadius;
        const List<LatLng> polyline = [
          LatLng(40.7128, -74.0060),
          LatLng(34.0522, -118.2437),
          LatLng(41.8781, -87.6298),
        ];

        final bool result = GeoMath.isPointOnPolyline(point: point, polyline: polyline, desiredRadius: radius);

        expect(result, true);
      });

      test('Test 3.18: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(40.7128, -74.0060);
        const double radius = GeoMath.earthRadius;
        const List<LatLng> polyline = [];

        final bool result = GeoMath.isPointOnPolyline(point: point, polyline: polyline, desiredRadius: radius);

        expect(result, false);
      });

      test('Test 3.19: testing isPointOnPolyline()', () {
        const LatLng point = LatLng(40.7128, -74.0060);
        const double radius = -100;
        const List<LatLng> polyline = [
          LatLng(40.7128, -74.0060),
          LatLng(34.0522, -118.2437),
          LatLng(41.8781, -87.6298),
        ];

        expect(() => GeoMath.isPointOnPolyline(point: point, polyline: polyline, desiredRadius: radius), throwsArgumentError);
      });
    });

    group('Testing getNextRoutePoint()', () {
      test('Test 4.0: testing getNextRoutePoint()', () {
        const LatLng currentLocation = LatLng(40.7128, -74.0060);
        const List<LatLng> route = [
          LatLng(40.7128, -74.0060),
          LatLng(34.0522, -118.2437),
          LatLng(41.8781, -87.6298),
        ];

        final int nextPointIndex = GeoMath.getNextRoutePoint(
            currentLocation: currentLocation, route: route);
        final LatLng nextPoint = route[nextPointIndex];

        expect(nextPoint, const LatLng(41.8781, -87.6298));
      });

      test('Test 4.1: testing getNextRoutePoint()', () {
        const LatLng currentLocation = LatLng(0, 0);
        const List<LatLng> route = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(1, 1),
        ];

        final int nextPointIndex = GeoMath.getNextRoutePoint(
            currentLocation: currentLocation, route: route);
        final LatLng nextPoint = route[nextPointIndex];

        expect(nextPoint, const LatLng(0, 1));
      });

      test('Test 4.2: testing getNextRoutePoint()', () {
        const LatLng currentLocation = LatLng(-1, 0);
        const List<LatLng> route = [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(1, 1),
        ];

        final int nextPointIndex = GeoMath.getNextRoutePoint(
            currentLocation: currentLocation, route: route);
        final LatLng nextPoint = route[nextPointIndex];

        expect(nextPoint, const LatLng(0, 0));
      });

      test('Test 4.3: testing getNextRoutePoint()', () {
        const LatLng currentLocation = LatLng(-1, 0);
        const List<LatLng> route = [];

        expect(
            () => GeoMath.getNextRoutePoint(
                currentLocation: currentLocation, route: route),
            throwsArgumentError);
      });

      test('Test 4.4: testing getNextRoutePoint()', () {
        const LatLng currentLocation = LatLng(-1, 0);
        const List<LatLng> route = [
          LatLng(0, 0)
        ];

        final int nextPointIndex = GeoMath.getNextRoutePoint(
            currentLocation: currentLocation, route: route);
        final LatLng nextPoint = route[nextPointIndex];

        expect(nextPoint, const LatLng(0, 0));
      });
    });

    group('Testing getDistanceToNextPoint()', () {
      test('Test 5.0: testing getDistanceToNextPoint()', () {
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

      test('Test 5.1: testing getDistanceToNextPoint()', () {
        const LatLng currentLocation = LatLng(0, 0);
        const List<LatLng> route = [];

        expect(() => GeoMath.getNextRoutePoint(
            currentLocation: currentLocation, route: route),
            throwsArgumentError);
      });
    });

    group('Testing getRouteCorners()', () {
      test('Test 6.0: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [];

        final LatLngBounds bounds =
            GeoMath.getRouteCorners(listOfRoutes: routes);

        expect(
            bounds,
            equals(LatLngBounds(
                southwest: const LatLng(0, 0), northeast: const LatLng(0, 0))));
      });

      test('Test 6.1: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [[], []];

        final LatLngBounds bounds =
            GeoMath.getRouteCorners(listOfRoutes: routes);

        expect(
            bounds,
            equals(LatLngBounds(
                southwest: const LatLng(0, 0), northeast: const LatLng(0, 0))));
      });

      test('Test 6.2: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [
          [LatLng(1.0, 2.0), LatLng(3.0, 4.0), LatLng(5.0, 6.0)],
          []
        ];

        final LatLngBounds bounds =
            GeoMath.getRouteCorners(listOfRoutes: routes);

        expect(
            bounds,
            equals(LatLngBounds(
                southwest: const LatLng(0, 0),
                northeast: const LatLng(0, 0))));
      });

      test('Test 6.3: testing getRouteCorners()', () {
        const List<List<LatLng>> routes = [
          [LatLng(1.0, 2.0), LatLng(3.0, 4.0), LatLng(5.0, 6.0)]
        ];

        final LatLngBounds bounds =
            GeoMath.getRouteCorners(listOfRoutes: routes);

        expect(
            bounds,
            equals(LatLngBounds(
                southwest: const LatLng(1, 2),
                northeast: const LatLng(5, 6))));
      });

      test('Test 6.4: testing getRouteCorners()', () {
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
      test('Test 7.0: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(0, 0);
        const LatLng nextPoint = LatLng(0, 1);

        final double result = GeoMath.calculateAzimuth(
            currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(90.0, 0.1));
      });

      test('Test 7.1: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(0, 0);
        const LatLng nextPoint = LatLng(1, 0);

        final double result = GeoMath.calculateAzimuth(
            currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(0.0, 0.1));
      });

      test('Test 7.2: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(0, 0);
        const LatLng nextPoint = LatLng(0, -1);

        final double result = GeoMath.calculateAzimuth(
            currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(270.0, 0.1));
      });

      test('Test 7.3: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(-1, 3);
        const LatLng nextPoint = LatLng(6, -19);

        final double result = GeoMath.calculateAzimuth(
            currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(287.8382, 0.1));
      });

      test('Test 7.4: testing calculateAzimuth()', () {
        const LatLng currentPoint = LatLng(-1, 3);
        const LatLng nextPoint = LatLng(-1.00001, 3.00001);

        final double result = GeoMath.calculateAzimuth(
            currentPoint: currentPoint, nextPoint: nextPoint);

        expect(result, closeTo(134.912, 0.1));
      });
    });

    group('Testing getDistanceToPoint()', () {
      test('Test 8.0: testing getDistanceToPoint()', () {
        const  LatLng currentLocation = LatLng(0.0, 0.0);
        const List<LatLng> route = [
          LatLng(1.0, 1.0),
          LatLng(2.0, 2.0),
          LatLng(3.0, 3.0),
        ];

        final double result = GeoMath.getDistanceToPoint(currentLocation: currentLocation, route: route);

        expect(result, closeTo(157249.5977681334, 0.01));
      });

      test('Test 8.1: testing getDistanceToPoint()', () {
        const LatLng currentLocation = LatLng(1.0, 1.0);
        const List<LatLng> route = [
          LatLng(1.0, 1.0),
          LatLng(2.0, 2.0),
          LatLng(3.0, 3.0),
        ];

        final double result = GeoMath.getDistanceToPoint(currentLocation: currentLocation, route: route);

        expect(result, 0.0);
      });

      test('Test 8.2: testing getDistanceToPoint()', () {
        const LatLng currentLocation = LatLng(1.0, 1.0);
        const List<LatLng> route = [];

        final double result = GeoMath.getDistanceToPoint(currentLocation: currentLocation, route: route);

        expect(result, 0.0);
      });
    });
  });

  group('Test geo_hash_utils library', () {

    group('Testing getGeoHashFromLocation()', () {
      test('Test 1.0: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(57.64911, 10.40744), precision: 9);
        expect(result, 'u4pruydqq');
      });

      test('Test 1.1: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(57.64911, 10.40744));
        expect(result, 'u4pruydqqvj');
      });

      test('Test 1.2: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(15.78390, 151.36217));
        expect(result, 'x6g9u36efhn');
      });

      test('Test 1.3: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(-5.28743, 31.29044));
        expect(result, 'kxn3bj3n2pe');
      });

      test('Test 1.4: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(38.82917, -1.7100));
        expect(result, 'eyyuchdu61g');
      });

      test('Test 1.5: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(-89.99999, -0.01001));
        expect(result, '5bpbpb08ncb');
      });

      test('Test 1.6: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(0, 0), precision: 4);
        expect(result, 's000');
      });

      test('Test 1.7: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(90, 0), precision: 4);
        expect(result, 'upbp');
      });

      test('Test 1.8: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(-90, 0), precision: 4);
        expect(result, 'h000');
      });

      test('Test 1.9: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(0.0000, 180.0000), precision: 9);
        expect(result, '800000000'); // In dependence on the algorithm, assigning a boundary point can work differently,
        // as the boundary point touches 2 or 4 geo hashes. as example, it could be xbpbpbpbp
      });

      test('Test 1.10: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(0.0000, -180.0000), precision: 9);
        expect(result, '800000000');
      });

      test('Test 1.11: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(0.0000, 179.999999), precision: 9);
        expect(result, 'xbpbpbpbp');
      });

      test('Test 1.12: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(0.045,0), precision: 9);
        expect(result, 's000200n0');
      });

      test('Test 1.13: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(0.045,0), precision: 1);
        expect(result, 's');
      });

      test('Test 1.14: testing getGeoHashFromLocation()', () {
        final String result = GeohashUtils.getGeoHashFromLocation(location: const LatLng(0.045,0), precision: 0);
        expect(result, '');
      });

      test('Test 1.15: testing getGeoHashFromLocation()', () {
        expect(() => GeohashUtils.getGeoHashFromLocation(location: const LatLng(0.045,0), precision: -1), throwsRangeError);
      });

    });

    group('Testing getLocationFromGeoHash()', () {
      test('Test 3.0: testing getLocationFromGeoHash()', () {
        final LatLng result = GeohashUtils.getLocationFromGeoHash(geohash: 'ezs41pbpc');
        expect(result.latitude, closeTo(42.5829863, 0.00001));
        expect(result.longitude, closeTo(-5.5810000, 0.00001));
      });

      test('Test 3.1: testing getLocationFromGeoHash()', () {
        expect(() => GeohashUtils.getLocationFromGeoHash(geohash: ''), throwsArgumentError);
      });

      test('Test 3.2: testing getLocationFromGeoHash()', () {
        expect(() => GeohashUtils.getLocationFromGeoHash(geohash: 'a'), throwsArgumentError);
      });
    });

    group('Testing getWayGeoHashes()', () {
      test('Test 4.0: testing getWayGeoHashes()', () {
        //https://geohash.softeng.co/
        //https://yandex.com.ge/maps/90/san-francisco/?ll=-122.402655%2C37.780473&mode=routes&rtext=37.785851%2C-122.406258~37.776081%2C-122.405098&rtt=auto&ruri=~&utm_medium=allapps&utm_source=face&z=15.77
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 0);
        expect(result, ['']);
      });

      test('Test 4.1: testing getWayGeoHashes()', () {
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 1);
        expect(result, ['9']);
      });

      test('Test 4.2: testing getWayGeoHashes()', () {
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 2);
        expect(result, ['9q']);
      });

      test('Test 4.3: testing getWayGeoHashes()', () {
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 3);
        expect(result, ['9q8']);
      });

      test('Test 4.4: testing getWayGeoHashes()', () {
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 4);
        expect(result, ['9q8y']);
      });

      test('Test 4.5: testing getWayGeoHashes()', () {
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 5);
        expect(result, ['9q8yy']);
      });

      test('Test 4.6: testing getWayGeoHashes()', () {
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 6);
        expect(result, ['9q8yyw', '9q8yyt', '9q8yys']);
      });

      test('Test 4.7: testing getWayGeoHashes()', () {
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 7);
        expect(result, [
          '9q8yywd', '9q8yywe', '9q8yyw7', '9q8yywk', '9q8yywj', '9q8yywn', '9q8yyty', '9q8yytz', '9q8yytx', '9q8yytw',
          '9q8yytq', '9q8yytm', '9q8yytj', '9q8yyth', '9q8yyt5', '9q8yysg'
        ]);
      });

      test('Test 4.8: testing getWayGeoHashes()', () {
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 8);
        expect(result, [
          '9q8yywdq', '9q8yywdt', '9q8yywdv', '9q8yywe5', '9q8yywe6', '9q8yywe9', '9q8yywe8', '9q8yyw7y', '9q8yywkk',
          '9q8yywk7', '9q8yywkd', '9q8yywk9', '9q8yywjp', '9q8yywjs', '9q8yywje', '9q8yywjf', '9q8yywjc', '9q8yywn0',
          '9q8yytyt', '9q8yytys', '9q8yytyu', '9q8yytyg', '9q8yytz4', '9q8yytz2', '9q8yytxr', '9q8yytxq', '9q8yytxh',
          '9q8yytx5', '9q8yytw9', '9q8yytw8', '9q8yytqq', '9q8yytqj', '9q8yytqh', '9q8yytq5', '9q8yytmf', '9q8yytm9',
          '9q8yytm2', '9q8yytjr', '9q8yythu', '9q8yyth6', '9q8yyt5b', '9q8yysgw', '9q8yysgm'
        ]);
      });

      test('Test 4.9: testing getWayGeoHashes()', () {
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 9);
        expect(result, [
          '9q8yywdqx', '9q8yywdqr', '9q8yywdqp', '9q8yywdtb', '9q8yywdtc', '9q8yywdtf', '9q8yywdvb', '9q8yywdvd',
          '9q8yywdvk', '9q8yywdvn', '9q8yywe5r', '9q8yywe6e', '9q8yywe93', '9q8yywe8g', '9q8yyw7yt', '9q8yyw7yw',
          '9q8yyw7yr', '9q8yywkk4', '9q8yywk7u', '9q8yywkdd', '9q8yywk9w', '9q8yywjp3', '9q8yywjs5', '9q8yywjeu',
          '9q8yywjf9', '9q8yywjcx', '9q8yywn0q', '9q8yytytf', '9q8yytysy', '9q8yytyu8', '9q8yytygt', '9q8yytz4d',
          '9q8yytz45', '9q8yytz2c', '9q8yytz23', '9q8yytz24', '9q8yytxrd', '9q8yytxr1', '9q8yytxq9', '9q8yytxq0',
          '9q8yytxhv', '9q8yytx52', '9q8yytw9p', '9q8yytw8v', '9q8yytqqu', '9q8yytqq0', '9q8yytqjn', '9q8yytqhe',
          '9q8yytqh6', '9q8yytq5b', '9q8yytmfd', '9q8yytm9y', '9q8yytm97', '9q8yytm2x', '9q8yytjrg', '9q8yytjr2',
          '9q8yythuc', '9q8yyth6e', '9q8yyt5bt', '9q8yysgwf', '9q8yysgmd'
        ]);
      });

      test('Test 4.10: testing getWayGeoHashes()', () {
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 10);
        expect(result, [
          '9q8yywdqx2', '9q8yywdqr3', '9q8yywdqpf', '9q8yywdtbq', '9q8yywdtc4', '9q8yywdtc8', '9q8yywdtf2',
          '9q8yywdvb2', '9q8yywdvdg', '9q8yywdvkp', '9q8yywdvnn', '9q8yywe5rk', '9q8yywe6e8', '9q8yywe93h',
          '9q8yywe8gf', '9q8yyw7ytz', '9q8yyw7yw9', '9q8yyw7yr5', '9q8yywkk45', '9q8yywk7u0', '9q8yywkdd2',
          '9q8yywk9wg', '9q8yywjp3y', '9q8yywjs55', '9q8yywjeub', '9q8yywjf9x', '9q8yywjcx8', '9q8yywn0q6',
          '9q8yytytf6', '9q8yytysyw', '9q8yytyu89', '9q8yytygt9', '9q8yytz4db', '9q8yytz45e', '9q8yytz2cp',
          '9q8yytz23z', '9q8yytz24p', '9q8yytxrdh', '9q8yytxr1z', '9q8yytxq95', '9q8yytxq02', '9q8yytxhv1',
          '9q8yytx52k', '9q8yytw9pq', '9q8yytw8vu', '9q8yytqqu1', '9q8yytqq0g', '9q8yytqjnj', '9q8yytqhe8',
          '9q8yytqh6g', '9q8yytq5by', '9q8yytmfdm', '9q8yytm9y5', '9q8yytm97d', '9q8yytm2xs', '9q8yytjrgv',
          '9q8yytjr29', '9q8yythucf', '9q8yyth6ev', '9q8yyt5bt2', '9q8yysgwfd', '9q8yysgmd7'
        ]);
      });

      test('Test 4.11: testing getWayGeoHashes()', () {
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 11);
        expect(result, [
          '9q8yywdqx2v', '9q8yywdqr3t', '9q8yywdqpfh', '9q8yywdtbq6', '9q8yywdtc49', '9q8yywdtc88', '9q8yywdtf2w',
          '9q8yywdvb28', '9q8yywdvdg4', '9q8yywdvkpr', '9q8yywdvnn4', '9q8yywe5rkm', '9q8yywe6e87', '9q8yywe93hy',
          '9q8yywe8gf2', '9q8yyw7ytz1', '9q8yyw7yw9w', '9q8yyw7yr5v', '9q8yywkk45k', '9q8yywk7u0p', '9q8yywkdd2c',
          '9q8yywk9wgn', '9q8yywjp3yh', '9q8yywjs55u', '9q8yywjeub8', '9q8yywjf9xj', '9q8yywjcx8p', '9q8yywn0q68',
          '9q8yytytf6e', '9q8yytysyw9', '9q8yytyu89t', '9q8yytygt9c', '9q8yytz4dbm', '9q8yytz45e7', '9q8yytz2cpy',
          '9q8yytz23zh', '9q8yytz24ps', '9q8yytxrdhu', '9q8yytxr1zu', '9q8yytxq95q', '9q8yytxq02b', '9q8yytxhv1x',
          '9q8yytx52kg', '9q8yytw9pq0', '9q8yytw8vue', '9q8yytqqu1d', '9q8yytqq0g6', '9q8yytqjnj2', '9q8yytqhe8v',
          '9q8yytqh6g2', '9q8yytq5byk', '9q8yytmfdm7', '9q8yytm9y5j', '9q8yytm97d7', '9q8yytm2xsh', '9q8yytjrgvt',
          '9q8yytjr29j', '9q8yythucfz', '9q8yyth6evb', '9q8yyt5bt2f', '9q8yysgwfdg', '9q8yysgmd7w'
        ]);
      });

      test('Test 4.12: testing getWayGeoHashes()', () {
        const List<LatLng> route = [
          LatLng(37.78585, -122.40626), LatLng(37.78581, -122.40626), LatLng(37.78577, -122.40624),
          LatLng(37.78575, -122.40622), LatLng(37.78573, -122.40619), LatLng(37.78572, -122.40617),
          LatLng(37.78572, -122.40613), LatLng(37.78572, -122.40588), LatLng(37.78569, -122.40577),
          LatLng(37.78567, -122.40571), LatLng(37.78562, -122.40563), LatLng(37.78531, -122.40523),
          LatLng(37.78516, -122.40505), LatLng(37.78497, -122.40481), LatLng(37.78487, -122.4047),
          LatLng(37.78451, -122.40427), LatLng(37.78448, -122.40423), LatLng(37.78445, -122.40421),
          LatLng(37.78406, -122.40374), LatLng(37.784, -122.40365), LatLng(37.78379, -122.40339),
          LatLng(37.78363, -122.40319), LatLng(37.78326, -122.40272), LatLng(37.78269, -122.40198),
          LatLng(37.78263, -122.40191), LatLng(37.78245, -122.4017), LatLng(37.78224, -122.40144),
          LatLng(37.78204, -122.40116), LatLng(37.78161, -122.40064), LatLng(37.78146, -122.40046),
          LatLng(37.78139, -122.40037), LatLng(37.78122, -122.40016), LatLng(37.78104, -122.39993),
          LatLng(37.78097, -122.3999), LatLng(37.78078, -122.39966), LatLng(37.78069, -122.39963),
          LatLng(37.78065, -122.39962), LatLng(37.78055, -122.39962), LatLng(37.78048, -122.39963),
          LatLng(37.78037, -122.39966), LatLng(37.78027, -122.3997), LatLng(37.78006, -122.39983),
          LatLng(37.77982, -122.40004), LatLng(37.77944, -122.40043), LatLng(37.77939, -122.40049),
          LatLng(37.77903, -122.40091), LatLng(37.77891, -122.40105), LatLng(37.77875, -122.40117),
          LatLng(37.77864, -122.40127), LatLng(37.77861, -122.40131), LatLng(37.77854, -122.40139),
          LatLng(37.77832, -122.40167), LatLng(37.77818, -122.40185), LatLng(37.77809, -122.40196),
          LatLng(37.77797, -122.40213), LatLng(37.77785, -122.40229), LatLng(37.77774, -122.40243),
          LatLng(37.77732, -122.40306), LatLng(37.77695, -122.40367), LatLng(37.77658, -122.40429),
          LatLng(37.77629, -122.40475), LatLng(37.77608, -122.4051),
        ];

        expect(() => GeohashUtils.getWayGeoHashes(points: route, precision: -1), throwsRangeError);
      });

      test('Test 4.13: testing getWayGeoHashes()', () {
        const List<LatLng> route = [];

        final List<String> result = GeohashUtils.getWayGeoHashes(points: route, precision: 0);
        expect(result, equals([]));
      });

    });

    group('Testing checkPointSideOnWay()', () {
      test('Test 5.0: testing checkPointSideOnWay()', () {
        const List<LatLng> sidePoints = [
          LatLng(0, 0),
          LatLng(1, 1),
          LatLng(2, 2),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
          LatLng(1, 2),
          LatLng(2, 3),
        ];

        final List<(int, String)> result = GeohashUtils.checkPointSideOnWay(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result.length, sidePoints.length);
        const List<(int, String)> expectations = [(0, 'right'), (1, 'right'), (2, 'right')];

        expect(result, expectations);
      });

      test('Test 5.1: testing checkPointSideOnWay()', () {
        const List<LatLng> sidePoints = [];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
          LatLng(1, 2),
          LatLng(2, 3),
        ];

        final List<(int, String)> result = GeohashUtils.checkPointSideOnWay(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, equals([]));
      });

      test('Test 5.2: testing checkPointSideOnWay()', () {
        const List<LatLng> sidePoints = [
          LatLng(0, 0),
          LatLng(1, 1),
          LatLng(2, 2),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
          LatLng(1, 2),
        ];

        final List<(int, String)> result = GeohashUtils.checkPointSideOnWay(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result.length, sidePoints.length);
        const List<(int, String)> expectations = [(0, 'right'), (1, 'right'), (2, 'right')];

        expect(result, expectations);
      });

      test('Test 5.3: testing checkPointSideOnWay()', () {
        const List<LatLng> sidePoints = [
          LatLng(0, 0),
          LatLng(1, 1),
          LatLng(2, 2),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
        ];

        expect(() => GeohashUtils.checkPointSideOnWay(sidePoints: sidePoints, wayPoints: wayPoints), throwsArgumentError);
      });
    });

    group('Testing alignSidePointsV1()', () {

      test('Test 6.0: testing alignSidePointsV1()', () {
        const List<LatLng> sidePoints = [
          LatLng(1.0, 2.0),
          LatLng(3.0, 4.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(5.0, 6.0),
          LatLng(7.0, 8.0),
        ];

        expect(() => GeohashUtils.alignSidePointsV1(sidePoints: sidePoints, wayPoints: wayPoints), throwsArgumentError );
      });

      test('Test 6.1: testing alignSidePointsV1()', () {
        const List<LatLng> sidePoints = [
          LatLng(1.0, 0.0),
          LatLng(2.0, 1.0),
          LatLng(3.0, 2.0),
          LatLng(4.0, 3.0),
          LatLng(5.0, 4.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(1.0, 1.0),
          LatLng(2.0, 2.0),
          LatLng(3.0, 3.0),
          LatLng(4.0, 4.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV1(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, const [
          LatLng(1.0, 0.0),
          LatLng(2.0, 1.0),
          LatLng(3.0, 2.0),
          LatLng(4.0, 3.0),
          LatLng(5.0, 4.0),
        ]);
      });

      test('Test 6.2: testing alignSidePointsV1()', () {
        const List<LatLng> sidePoints = [
          LatLng(1.0, 0.0),
          LatLng(2.0, 1.0),
          LatLng(3.0, 2.0),
          LatLng(4.0, 3.0),
          LatLng(5.0, 4.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(4.0, 4.0),
          LatLng(3.0, 3.0),
          LatLng(2.0, 2.0),
          LatLng(1.0, 1.0),
          LatLng(0.0, 0.0),
        ];

        expect(() => GeohashUtils.alignSidePointsV1(sidePoints: sidePoints, wayPoints: wayPoints), throwsArgumentError );
      });

      test('Test 6.3: testing alignSidePointsV1()', () {
        const List<LatLng> sidePoints = [
          LatLng(1.0, 0.0),
          LatLng(2.0, 1.0),
          LatLng(3.0, 2.0),
          LatLng(4.0, 3.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(4.0, 4.0),
          LatLng(3.0, 3.0),
          LatLng(2.0, 2.0),
          LatLng(1.0, 1.0),
          LatLng(0.0, 0.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV1(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, const [
          LatLng(4.0, 3.0),
          LatLng(3.0, 2.0),
          LatLng(2.0, 1.0),
          LatLng(1.0, 0.0),
        ]);
      });

      test('Test 6.4: testing alignSidePointsV1()', () {
        const List<LatLng> sidePoints = [
          LatLng(0.0, -2.0),
          LatLng(-2.0, 1.0),
          LatLng(3.0, 0.0),
          LatLng(4.0, 3.0),
          LatLng(1.0, 4.0),
          LatLng(2.0, 6.0),
          LatLng(4.0, 7.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(3.0, 4.0),
        ];

        expect(() => GeohashUtils.alignSidePointsV1(sidePoints: sidePoints, wayPoints: wayPoints), throwsArgumentError);
      });

      test('Test 6.5: testing alignSidePointsV1()', () {
        const List<LatLng> sidePoints = [
          LatLng(3.0, 0.0),
          LatLng(4.0, 3.0),
          LatLng(1.0, 4.0),
          LatLng(2.0, 6.0),
          LatLng(4.0, 7.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(3.0, 4.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV1(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, const [
          LatLng(3.0, 0.0),
          LatLng(4.0, 3.0),
          LatLng(1.0, 4.0),
          LatLng(2.0, 6.0),
          LatLng(4.0, 7.0)
        ]);
      });

      test('Test 6.6: testing alignSidePointsV1()', () {
        const List<LatLng> sidePoints = [
          LatLng(3.0, 4.0),
          LatLng(4.0, 3.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(3.0, 4.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV1(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, const [LatLng(3.0, 4.0), LatLng(4.0, 3.0)]);
      });

      test('Test 6.7: testing alignSidePointsV1()', () {
        const List<LatLng> sidePoints = [
          LatLng(-1.0, 4.0),
          LatLng(4.0, 3.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(3.0, 4.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV1(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, const [LatLng(4.0, 3.0), LatLng(-1.0, 4.0)]);
      });
    });

    group('Testing alignSidePointsV2()', () {

      test('Test 6.0: testing alignSidePointsV2()', () {
        const List<LatLng> sidePoints = [
          LatLng(1.0, 2.0),
          LatLng(3.0, 4.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(5.0, 6.0),
          LatLng(7.0, 8.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV2(sidePoints: sidePoints, wayPoints: wayPoints);
        expect(result, const [LatLng(1.0, 2.0), LatLng(3.0, 4.0)]);
      });

      test('Test 6.1: testing alignSidePointsV2()', () {
        const List<LatLng> sidePoints = [
          LatLng(1.0, 0.0),
          LatLng(2.0, 1.0),
          LatLng(3.0, 2.0),
          LatLng(4.0, 3.0),
          LatLng(5.0, 4.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(1.0, 1.0),
          LatLng(2.0, 2.0),
          LatLng(3.0, 3.0),
          LatLng(4.0, 4.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV2(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, const [
          LatLng(1.0, 0.0),
          LatLng(2.0, 1.0),
          LatLng(3.0, 2.0),
          LatLng(4.0, 3.0),
          LatLng(5.0, 4.0),
        ]);
      });

      test('Test 6.2: testing alignSidePointsV2()', () {
        const List<LatLng> sidePoints = [
          LatLng(1.0, 0.0),
          LatLng(2.0, 1.0),
          LatLng(3.0, 2.0),
          LatLng(4.0, 3.0),
          LatLng(5.0, 4.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(4.0, 4.0),
          LatLng(3.0, 3.0),
          LatLng(2.0, 2.0),
          LatLng(1.0, 1.0),
          LatLng(0.0, 0.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV2(sidePoints: sidePoints, wayPoints: wayPoints);
        expect(result, const [
          LatLng(5.0, 4.0),
          LatLng(4.0, 3.0),
          LatLng(3.0, 2.0),
          LatLng(2.0, 1.0),
          LatLng(1.0, 0.0)
        ]);
      });

      test('Test 6.3: testing alignSidePointsV2()', () {
        const List<LatLng> sidePoints = [
          LatLng(1.0, 0.0),
          LatLng(2.0, 1.0),
          LatLng(3.0, 2.0),
          LatLng(4.0, 3.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(4.0, 4.0),
          LatLng(3.0, 3.0),
          LatLng(2.0, 2.0),
          LatLng(1.0, 1.0),
          LatLng(0.0, 0.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV2(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, const [
          LatLng(4.0, 3.0),
          LatLng(3.0, 2.0),
          LatLng(2.0, 1.0),
          LatLng(1.0, 0.0),
        ]);
      });

      test('Test 6.4: testing alignSidePointsV2()', () {
        const List<LatLng> sidePoints = [
          LatLng(0.0, -2.0),
          LatLng(-2.0, 1.0),
          LatLng(3.0, 0.0),
          LatLng(4.0, 3.0),
          LatLng(1.0, 4.0),
          LatLng(2.0, 6.0),
          LatLng(4.0, 7.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(3.0, 4.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV2(sidePoints: sidePoints, wayPoints: wayPoints);
        expect(result, const [
          LatLng(3.0, 0.0),
          LatLng(-2.0, 1.0),
          LatLng(0.0, -2.0),
          LatLng(4.0, 3.0),
          LatLng(1.0, 4.0),
          LatLng(2.0, 6.0),
          LatLng(4.0, 7.0)
        ]);
      });

      test('Test 6.5: testing alignSidePointsV2()', () {
        const List<LatLng> sidePoints = [
          LatLng(3.0, 0.0),
          LatLng(4.0, 3.0),
          LatLng(1.0, 4.0),
          LatLng(2.0, 6.0),
          LatLng(4.0, 7.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(3.0, 4.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV2(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, const [
          LatLng(3.0, 0.0),
          LatLng(4.0, 3.0),
          LatLng(1.0, 4.0),
          LatLng(2.0, 6.0),
          LatLng(4.0, 7.0)
        ]);
      });

      test('Test 6.6: testing alignSidePointsV2()', () {
        const List<LatLng> sidePoints = [
          LatLng(3.0, 4.0),
          LatLng(4.0, 3.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(3.0, 4.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV2(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, const [LatLng(3.0, 4.0), LatLng(4.0, 3.0)]);
      });

      test('Test 6.7: testing alignSidePointsV2()', () {
        const List<LatLng> sidePoints = [
          LatLng(-1.0, 4.0),
          LatLng(4.0, 3.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(3.0, 4.0),
        ];

        final List<LatLng> result = GeohashUtils.alignSidePointsV2(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, const [LatLng(4.0, 3.0), LatLng(-1.0, 4.0)]);
      });
    });

    group('Testing areSidePointsInFrontOfTheRoad()', () {

      test('Test 7.0: testing areSidePointsInFrontOfTheRoad()', () {
        const List<LatLng> sidePoints = [
          LatLng(1.0, 2.0),
          LatLng(3.0, 4.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(5.0, 6.0),
          LatLng(7.0, 8.0),
        ];

        final bool result = GeohashUtils.areSidePointsInFrontOfTheRoad(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, true);
      });

      test('Test 7.1: testing areSidePointsInFrontOfTheRoad()', () {
        const List<LatLng> sidePoints = [
          LatLng(1.0, 0.0),
          LatLng(2.0, 1.0),
          LatLng(3.0, 2.0),
          LatLng(4.0, 3.0),
          LatLng(5.0, 4.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(1.0, 1.0),
          LatLng(2.0, 2.0),
          LatLng(3.0, 3.0),
          LatLng(4.0, 4.0),
        ];

        final bool result = GeohashUtils.areSidePointsInFrontOfTheRoad(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, true);
      });

      test('Test 7.2: testing areSidePointsInFrontOfTheRoad()', () {
        const List<LatLng> sidePoints = [
          LatLng(1.0, 0.0),
          LatLng(2.0, 1.0),
          LatLng(3.0, 2.0),
          LatLng(4.0, 3.0),
          LatLng(5.0, 4.0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(4.0, 4.0),
          LatLng(3.0, 3.0),
          LatLng(2.0, 2.0),
          LatLng(1.0, 1.0),
          LatLng(0.0, 0.0),
        ];

        final bool result = GeohashUtils.areSidePointsInFrontOfTheRoad(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, false);
      });

      test('Test 7.3: testing areSidePointsInFrontOfTheRoad()', () {
        const List<LatLng> sidePoints = [];

        const List<LatLng> wayPoints = [
          LatLng(0.0, 0.0),
          LatLng(5.0, 6.0),
          LatLng(7.0, 8.0),
        ];

        final bool result = GeohashUtils.areSidePointsInFrontOfTheRoad(sidePoints: sidePoints, wayPoints: wayPoints);

        expect(result, true);
      });

      test('Test 7.4: testing areSidePointsInFrontOfTheRoad()', () {
        const List<LatLng> sidePoints = [];

        const List<LatLng> wayPoints = [];

        expect(() => GeohashUtils.areSidePointsInFrontOfTheRoad(sidePoints: sidePoints, wayPoints: wayPoints), throwsArgumentError);
      });
    });

    group('Testing dotProductionByPoints()', () {
      test('Test 8.0: dotProductionByPoints()', () {
        const LatLng A = LatLng(0.0, 0.0);
        const LatLng B = LatLng(0.0, 1.0);
        const LatLng C = LatLng(0.0, 1.0);

        final double result = GeohashUtils.dotProductionByPoints(A: A, B: B, C: C);
        expect(result, 1);
      });

      test('Test 8.1: dotProductionByPoints()', () {
        const LatLng A = LatLng(0.0, 0.0);
        const LatLng B = LatLng(0.0, 1.0);
        const LatLng C = LatLng(1.0, 1.0);

        final double result = GeohashUtils.dotProductionByPoints(A: A, B: B, C: C);
        expect(result, 1);
      });

      test('Test 8.2: dotProductionByPoints()', () {
        const LatLng A = LatLng(0.0, 0.0);
        const LatLng B = LatLng(0.0, 1.0);
        const LatLng C = LatLng(1.0, 0.0);

        final double result = GeohashUtils.dotProductionByPoints(A: A, B: B, C: C);
        expect(result, 0);
      });

      test('Test 8.3: dotProductionByPoints()', () {
        const LatLng A = LatLng(0.0, 0.0);
        const LatLng B = LatLng(0.0, 1.0);
        const LatLng C = LatLng(1.0, -1.0);

        final double result = GeohashUtils.dotProductionByPoints(A: A, B: B, C: C);
        expect(result, -1);
      });

      test('Test 8.4: dotProductionByPoints()', () {
        const LatLng A = LatLng(0.0, 0.0);
        const LatLng B = LatLng(0.0, 1.0);
        const LatLng C = LatLng(0.0, -1.0);

        final double result = GeohashUtils.dotProductionByPoints(A: A, B: B, C: C);
        expect(result, -1);
      });

      test('Test 8.5: dotProductionByPoints()', () {
        const LatLng A = LatLng(0.0, 0.0);
        const LatLng B = LatLng(0.0, 1.0);
        const LatLng C = LatLng(-1.0, -1.0);

        final double result = GeohashUtils.dotProductionByPoints(A: A, B: B, C: C);
        expect(result, -1);
      });

      test('Test 8.6: dotProductionByPoints()', () {
        const LatLng A = LatLng(0.0, 0.0);
        const LatLng B = LatLng(0.0, 1.0);
        const LatLng C = LatLng(-1.0, 0.0);

        final double result = GeohashUtils.dotProductionByPoints(A: A, B: B, C: C);
        expect(result, 0);
      });

      test('Test 8.7: dotProductionByPoints()', () {
        const LatLng A = LatLng(0.0, 0.0);
        const LatLng B = LatLng(0.0, 1.0);
        const LatLng C = LatLng(-1.0, 1.0);

        final double result = GeohashUtils.dotProductionByPoints(A: A, B: B, C: C);
        expect(result, 1);
      });

    });

    group('Testing checkPointSideOnWay3()', () {
      test('Test 9.0: testing checkPointSideOnWay3()', () {
        const List<LatLng> sidePoints = [
          LatLng(0, 0),
          LatLng(1, 1),
          LatLng(2, 2),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
          LatLng(1, 2),
          LatLng(2, 3),
        ];

        final List<(int, String, String)> result = GeohashUtils.checkPointSideOnWay3(sidePoints: sidePoints, wayPoints: wayPoints, currentPosition: const LatLng(1, 2));

        expect(result.length, sidePoints.length);
        const List<(int, String, String)> expectations = [(0, 'right', 'past'), (1, 'right', 'next'), (2, 'right', 'onWay')];

        expect(result, expectations);
      });

      test('Test 9.1: testing checkPointSideOnWay3()', () {
        const List<LatLng> sidePoints = [];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
          LatLng(1, 2),
          LatLng(2, 3),
        ];

        final List<(int, String, String)> result = GeohashUtils.checkPointSideOnWay3(sidePoints: sidePoints, wayPoints: wayPoints, currentPosition: const LatLng(1, 2));

        expect(result, equals([]));
      });

      test('Test 9.2: testing checkPointSideOnWay3()', () {
        const List<LatLng> sidePoints = [
          LatLng(0, 0),
          LatLng(1, 1),
          LatLng(2, 2),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
          LatLng(1, 2),
        ];

        final List<(int, String, String)> result = GeohashUtils.checkPointSideOnWay3(sidePoints: sidePoints, wayPoints: wayPoints, currentPosition: const LatLng(1, 2));

        expect(result.length, sidePoints.length);
        const List<(int, String, String)> expectations = [(0, 'right', 'past'), (1, 'right', 'next'), (2, 'right', 'onWay')];

        expect(result, expectations);
      });

      test('Test 9.3: testing checkPointSideOnWay3()', () {
        const List<LatLng> sidePoints = [
          LatLng(0, 0),
          LatLng(1, 1),
          LatLng(2, 2),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
        ];

        expect(() => GeohashUtils.checkPointSideOnWay3(sidePoints: sidePoints, wayPoints: wayPoints, currentPosition: const LatLng(0, 1),), throwsArgumentError);
      });

      test('Test 9.4: testing checkPointSideOnWay3()', () {
        const List<LatLng> sidePoints = [
          LatLng(0, 0),
          LatLng(1, 1),
          LatLng(2, 2),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
          LatLng(1, 2),
          LatLng(2, 3),
        ];

        final List<(int, String, String)> result = GeohashUtils.checkPointSideOnWay3(sidePoints: sidePoints, wayPoints: wayPoints, currentPosition: const LatLng(0, 1));

        expect(result.length, sidePoints.length);
        const List<(int, String, String)> expectations = [(0, 'right', 'next'), (1, 'right', 'onWay'), (2, 'right', 'onWay')];

        expect(result, expectations);
      });

      test('Test 9.5: testing checkPointSideOnWay3()', () {
        const List<LatLng> sidePoints = [
          LatLng(0, 0),
          LatLng(1, 1),
          LatLng(2, 2),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
          LatLng(1, 2),
          LatLng(2, 3),
        ];

        final List<(int, String, String)> result = GeohashUtils.checkPointSideOnWay3(sidePoints: sidePoints, wayPoints: wayPoints, currentPosition: const LatLng(2, 3));

        expect(result.length, sidePoints.length);
        const List<(int, String, String)> expectations = [(0, 'right', 'past'), (1, 'right', 'past'), (2, 'right', 'next')];

        expect(result, expectations);
      });

      test('Test 9.6: testing checkPointSideOnWay3()', () {
        const List<LatLng> sidePoints = [
          LatLng(0, 0),
          LatLng(1, 1),
          LatLng(2, 2),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
          LatLng(1, 2),
        ];

        final List<(int, String, String)> result = GeohashUtils.checkPointSideOnWay3(sidePoints: sidePoints, wayPoints: wayPoints, currentPosition: const LatLng(0, 1));

        expect(result.length, sidePoints.length);
        const List<(int, String, String)> expectations = [(0, 'right', 'next'), (1, 'right', 'onWay'), (2, 'right', 'onWay')];

        expect(result, expectations);
      });

      test('Test 9.7: testing checkPointSideOnWay3()', () {
        const List<LatLng> sidePoints = [
          LatLng(1, 1),
          LatLng(0, 0),
          LatLng(2, 2),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
          LatLng(1, 2),
          LatLng(2, 3),
        ];

        final List<(int, String, String)> result = GeohashUtils.checkPointSideOnWay3(sidePoints: sidePoints, wayPoints: wayPoints, currentPosition: const LatLng(1, 2));

        expect(result.length, sidePoints.length);
        const List<(int, String, String)> expectations = [(0, 'right', 'past'), (1, 'right', 'next'), (2, 'right', 'onWay')];

        expect(result, expectations);
      });

      test('Test 9.8: testing checkPointSideOnWay3()', () {
        const List<LatLng> sidePoints = [
          LatLng(0, 0),
        ];

        const List<LatLng> wayPoints = [
          LatLng(0, 1),
          LatLng(1, 2),
        ];

        final List<(int, String, String)> result = GeohashUtils.checkPointSideOnWay3(sidePoints: sidePoints, wayPoints: wayPoints, currentPosition: const LatLng(1, 2));

        expect(result.length, sidePoints.length);
        const List<(int, String, String)> expectations = [(0, 'right', 'next')];

        expect(result, expectations);
      });
    });

    group('Testing getRouteLengthBetweenPoints()', () {
      test('Test 10.0: testing getRouteLengthBetweenPoints()', () {
        const LatLng start = LatLng(0, 0);
        const LatLng end = LatLng(5, 5);
        const List<LatLng> route = [
          LatLng(0, 0),
          LatLng(1, 1),
          LatLng(2, 2),
          LatLng(3, 3),
          LatLng(4, 4),
          LatLng(5, 5),
        ];


        final double result = GeohashUtils.getRouteLengthBetweenPoints(start: start, end: end, route: route);
        const double expectations = 785768.3026627927;

        expect(result, closeTo(expectations, 2));
      });

      test('Test 10.1: testing getRouteLengthBetweenPoints()', () {
        const LatLng start = LatLng(0, 0);
        const LatLng end = LatLng(1, 1);
        const List<LatLng> route = [
          LatLng(0, 0),
          LatLng(1, 1),
        ];


        final double result = GeohashUtils.getRouteLengthBetweenPoints(start: start, end: end, route: route);
        const double expectations = 157249.6034104515;

        expect(result, expectations);
      });

      test('Test 10.2: testing getRouteLengthBetweenPoints()', () {
        const LatLng start = LatLng(4, 4);
        const LatLng end = LatLng(5, 5);
        const List<LatLng> route = [
          LatLng(4, 4),
          LatLng(5, 5),
        ];


        final double result = GeohashUtils.getRouteLengthBetweenPoints(start: start, end: end, route: route);
        const double expectations = 157010.38444117695;

        expect(result, expectations);
      });

      test('Test 10.3: testing getRouteLengthBetweenPoints()', () {
        const LatLng start = LatLng(5, 5);
        const LatLng end = LatLng(0, 0);
        const List<LatLng> route = [
          LatLng(0, 0),
          LatLng(1, 1),
          LatLng(2, 2),
          LatLng(3, 3),
          LatLng(4, 4),
          LatLng(5, 5),
        ];


        final double result = GeohashUtils.getRouteLengthBetweenPoints(start: start, end: end, route: route);
        const double expectations = 785768.3026627927;

        expect(result, closeTo(expectations, 2));
      });

      test('Test 10.4: testing getRouteLengthBetweenPoints()', () {
        const LatLng start = LatLng(0, 0);
        const LatLng end = LatLng(5, 5);
        const List<LatLng> route = [
          LatLng(5, 5),
          LatLng(4, 4),
          LatLng(3, 3),
          LatLng(2, 2),
          LatLng(1, 1),
          LatLng(0, 0),
        ];


        final double result = GeohashUtils.getRouteLengthBetweenPoints(start: start, end: end, route: route);
        const double expectations = 785768.3026627927;

        expect(result, closeTo(expectations, 2));
      });

      test('Test 10.5: testing getRouteLengthBetweenPoints()', () {
        const LatLng start = LatLng(1, 1);
        const LatLng end = LatLng(4, 4);
        const List<LatLng> route = [
          LatLng(5, 5),
          LatLng(4, 4),
          LatLng(3, 3),
          LatLng(2, 2),
          LatLng(1, 1),
          LatLng(0, 0),
        ];

        final double result = GeohashUtils.getRouteLengthBetweenPoints(start: start, end: end, route: route);
        const double expectations = 471509.20218584;

        expect(result, closeTo(expectations, 2));
      });

      test('Test 10.6: testing getRouteLengthBetweenPoints()', () {
        const LatLng start = LatLng(1, 1);
        const LatLng end = LatLng(1, 1);
        const List<LatLng> route = [
          LatLng(5, 5),
          LatLng(4, 4),
          LatLng(3, 3),
          LatLng(2, 2),
          LatLng(1, 1),
          LatLng(0, 0),
        ];

        final double result = GeohashUtils.getRouteLengthBetweenPoints(start: start, end: end, route: route);
        const double expectations = 0;

        expect(result, expectations);
      });

      test('Test 10.7: testing getRouteLengthBetweenPoints()', () {
        const LatLng start = LatLng(1, 1);
        const LatLng end = LatLng(4, 4);
        const List<LatLng> route = [];

        expect(() => GeohashUtils.getRouteLengthBetweenPoints(start: start, end: end, route: route), throwsArgumentError);
      });

      test('Test 10.8: testing getRouteLengthBetweenPoints()', () {
        const LatLng start = LatLng(-1, 1);
        const LatLng end = LatLng(4, 4);
        const List<LatLng> route = [
          LatLng(5, 5),
          LatLng(4, 4),
          LatLng(3, 3),
          LatLng(2, 2),
          LatLng(1, 1),
          LatLng(0, 0),
        ];

        expect(() => GeohashUtils.getRouteLengthBetweenPoints(start: start, end: end, route: route), throwsArgumentError);
      });

      test('Test 10.9: testing getRouteLengthBetweenPoints()', () {
        const LatLng start = LatLng(1, 1);
        const LatLng end = LatLng(-4, 4);
        const List<LatLng> route = [
          LatLng(5, 5),
          LatLng(4, 4),
          LatLng(3, 3),
          LatLng(2, 2),
          LatLng(1, 1),
          LatLng(0, 0),
        ];

        expect(() => GeohashUtils.getRouteLengthBetweenPoints(start: start, end: end, route: route), throwsArgumentError);
      });
    });
  });

}

