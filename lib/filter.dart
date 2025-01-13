import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

//ordinary max acceleration for truck is about 3.5 m/s^2
//6 m/s - 21.6 km/h
//5 m/s - 18.0 km/h
//4 m/s - 14.4 km/h
//3 m/s - 10.8 km/h
//2 m/s - 7.2 km/h
//1 m/s - 3.6 km/h
class LocationFilter {
  LocationFilter({double maxAbsAcc = 4}) {
    _maxAbsAcc = maxAbsAcc;
  }

  Position? _prevPos;
  Position? _prePrevPos;

  //maximal absolute acceleration
  double _maxAbsAcc = 0;

  static const double earthRadiusInMeters = 6371009.0;

  /// Degrees to radians.
  static double toRadians(double deg) {
    return deg * (math.pi / 180);
  }

  /// Radians to degrees.
  static double toDegrees(double rad) {
    return rad * (180 / math.pi);
  }

  /// Get distance between two points.
  static double getDistance(LatLng point1, LatLng point2) {
    final double deltaLat = toRadians(point2.latitude - point1.latitude);
    final double deltaLon = toRadians(point2.longitude - point1.longitude);

    final double haversinLat = math.pow(math.sin(deltaLat / 2), 2).toDouble();
    final double haversinLon = math.pow(math.sin(deltaLon / 2), 2).toDouble();
    final double parameter = math.cos(toRadians(point1.latitude)) *
        math.cos(toRadians(point2.latitude));
    final double asinArgument =
        math.sqrt(haversinLat + haversinLon * parameter).clamp(-1, 1);

    return earthRadiusInMeters * 2 * math.asin(asinArgument);
  }

  Position checkThePosition(Position curPos) {
    if (curPos.isMocked) {
      print('[GeoUtils]: location is mocked - filter not working');
      return curPos;
    } else if (_prevPos == null) {
      _prevPos = curPos;
      return curPos;
    } else if (_prePrevPos == null) {
      _prePrevPos = _prevPos;
      _prevPos = curPos;
      return curPos;
    }
    final LatLng prePrevPos =
        LatLng(_prePrevPos!.latitude, _prePrevPos!.longitude);
    final LatLng prevPos = LatLng(_prevPos!.latitude, _prevPos!.longitude);
    final LatLng currentPos = LatLng(curPos.latitude, curPos.longitude);

    //in seconds
    final double startTime =
        (_prevPos!.timestamp.millisecondsSinceEpoch.toDouble() -
                _prePrevPos!.timestamp.millisecondsSinceEpoch.toDouble()) /
            1000;
    //in seconds
    final double currentTime =
        (curPos.timestamp.millisecondsSinceEpoch.toDouble() -
                _prevPos!.timestamp.millisecondsSinceEpoch.toDouble()) /
            1000;

    final double startSpeed = getDistance(prePrevPos, prevPos) / startTime;
    final double currentSpeed = getDistance(prevPos, currentPos) / currentTime;

    //acceleration
    final double acc = (currentSpeed - startSpeed) / currentTime;
    if (_maxAbsAcc > acc.abs()) return _prevPos!;

    _prePrevPos = _prevPos;
    _prevPos = curPos;

    return curPos;
  }
}
