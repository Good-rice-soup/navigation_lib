import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

//ignore_for_file: avoid_classes_with_only_static_members
class NavigationUtils{
  NavigationUtils();

  static LatLngBounds expandBounds(LatLngBounds bounds, double factor) {
    final double lat =
    (bounds.northeast.latitude - bounds.southwest.latitude).abs();
    final double lng =
    (bounds.northeast.longitude - bounds.southwest.longitude).abs();
    final LatLng southwest = LatLng(
      bounds.southwest.latitude - (lat * (factor - 1) / 2),
      bounds.southwest.longitude - (lng * (factor - 1) / 2),
    );
    final LatLng northeast = LatLng(
      bounds.northeast.latitude + (lat * (factor - 1) / 2),
      bounds.northeast.longitude + (lng * (factor - 1) / 2),
    );

    return LatLngBounds(southwest: southwest, northeast: northeast);
  }
}