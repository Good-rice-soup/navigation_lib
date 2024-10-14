import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

class RouteCutter {
  List<LatLng> cutRoute({
    required List<LatLng> originalRoute,
    required List<LatLng> simplifiedRoute,
    required int nextPointIndexOnOriginalRoute,
    required LatLng currentLocation,
    required LatLngBounds bounds,
    required int maxZoomForRepaintRoute,
    required int currentZoomLevel,
  }) {
    // Map to store original route points with their indices
    final Map<String, int> originalPointToIndex = {};
    for (int i = 0; i < originalRoute.length; i++) {
      final LatLng point = originalRoute[i];
      final String key = _getKey(point);
      originalPointToIndex[key] = i;
    }

    // List to store corresponding indices in the original route
    final List<int> originalIndices = [];
    for (int i = 0; i < simplifiedRoute.length; i++) {
      final LatLng point = simplifiedRoute[i];
      final String key = _getKey(point);
      final int? originalIndex = originalPointToIndex[key];
      if (originalIndex != null) {
        originalIndices.add(originalIndex);
      } else {
        // If point not found, find the nearest point in the original route
        final int nearestIndex = _findNearestPointIndex(point, originalRoute);
        originalIndices.add(nearestIndex);
      }
    }

    // Find the cut index in the simplified route
    int cutIndex = 0;
    for (int i = 0; i < originalIndices.length; i++) {
      if (originalIndices[i] >= nextPointIndexOnOriginalRoute) {
        cutIndex = i;
        break;
      }
    }

    // Cut the simplified route from the cut index
    List<LatLng> newRoute = simplifiedRoute.sublist(cutIndex);

    // If current zoom level is greater than or equal to maxZoomForRepaintRoute, replace simplified route with original within bounds
    if (currentZoomLevel >= maxZoomForRepaintRoute) {
      // Extract the original route segment within bounds
      final List<LatLng> detailedSegment = [];
      for (int i = nextPointIndexOnOriginalRoute;
          i < originalRoute.length;
          i++) {
        final LatLng point = originalRoute[i];
        if (bounds.contains(point)) {
          detailedSegment.add(point);
        } else if (detailedSegment.isNotEmpty) {
          // Break the loop if we've exited the bounds after collecting points
          break;
        }
      }

      // Replace the corresponding segment in newRoute with detailedSegment
      newRoute = _replaceSegmentWithinBounds(
        simplifiedRoute: newRoute,
        detailedSegment: detailedSegment,
        bounds: bounds,
      );
    }

    // Cut the route at currentLocation and add it as the first point
    return _cutRouteAtCurrentLocation(
      route: newRoute,
      currentLocation: currentLocation,
    );
  }

  // Helper method to generate a unique key for a LatLng point
  String _getKey(LatLng point) {
    final double lat = double.parse(point.latitude.toStringAsFixed(6));
    final double lng = double.parse(point.longitude.toStringAsFixed(6));
    return '$lat,$lng';
  }

  // Helper method to find the nearest point index in the original route
  int _findNearestPointIndex(LatLng point, List<LatLng> route) {
    double minDistance = double.infinity;
    int nearestIndex = 0;
    for (int i = 0; i < route.length; i++) {
      final double distance = _distanceBetweenPoints(point, route[i]);
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    return nearestIndex;
  }

  // Helper method to calculate squared distance between two points
  double _distanceBetweenPoints(LatLng a, LatLng b) {
    final double dx = a.latitude - b.latitude;
    final double dy = a.longitude - b.longitude;
    return dx * dx + dy * dy;
  }

  // Helper method to replace segment within bounds with detailed segment
  List<LatLng> _replaceSegmentWithinBounds({
    required List<LatLng> simplifiedRoute,
    required List<LatLng> detailedSegment,
    required LatLngBounds bounds,
  }) {
    // Remove simplified route points within bounds
    simplifiedRoute.where((point) => !bounds.contains(point)).toList();

    // Find the indices where the bounds start and end in the simplified route
    int startIndex = 0;
    for (int i = 0; i < simplifiedRoute.length; i++) {
      if (bounds.contains(simplifiedRoute[i])) {
        startIndex = i;
        break;
      }
    }

    int endIndex = startIndex;
    for (int i = startIndex; i < simplifiedRoute.length; i++) {
      if (!bounds.contains(simplifiedRoute[i])) {
        endIndex = i;
        break;
      } else if (i == simplifiedRoute.length - 1) {
        endIndex = simplifiedRoute.length;
      }
    }

    // Build the new route by inserting the detailed segment
    final List<LatLng> newRoute = [
      ...simplifiedRoute.sublist(0, startIndex),
      ...detailedSegment,
      ...simplifiedRoute.sublist(endIndex)
    ];

    return newRoute;
  }

  // Helper method to cut the route at currentLocation and add it as the first point
  List<LatLng> _cutRouteAtCurrentLocation({
    required List<LatLng> route,
    required LatLng currentLocation,
  }) {
    // Find the closest point in the route to currentLocation
    final int nearestIndex = _findNearestPointIndex(currentLocation, route);

    // Cut the route from the nearest index and add currentLocation as the first point
    final List<LatLng> cutRoute = route
      ..sublist(nearestIndex)
      ..insert(0, currentLocation);

    return cutRoute;
  }
}
