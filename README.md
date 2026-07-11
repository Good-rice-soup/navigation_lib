A highly optimised library for analysing movement along a route and rendering it directly on-device. It can operate
across multiple isolates, cache its own state, and restore from it instantly. Every capability is fully configurable —
the developer decides which ones to use.

## What it's for

- **Progress tracking** — where the user is along the route, how far they've come, and whether they've gone off-route.
- **Points of interest** — track points attached to the route and their state relative to the user (passed / upcoming /
  on the way / removed).
- **Zoom-aware rendering** — get the route polyline simplified to the level of detail each map zoom level needs.
- **Save & restore** — persist navigation state to disk and reload it later.

## Installation

Not published to pub.dev; depend on it via git, pinned to a release tag:

```yaml
dependencies:
  navigation_lib:
    git:
      url: https://github.com/Good-rice-soup/navigation_lib.git
      ref: v7.0.0
```

```dart
import 'package:navigation_lib/navigation_lib.dart';
```

Coordinates use `LatLng` / `LatLngBounds` from `google_maps_flutter_platform_interface`.

## API

Everything is exported from `package:navigation_lib/navigation_lib.dart`. Main entry points:

- `RouteManager` — the navigation computer: feed it positions, read back progress and side-point state.
- `RouteDataEngine` — owns a route's data and handles persistence.
- `PolylineSimplifier` — builds zoom-dependent simplified routes.
- `ZoomConfig` / `RouteSimplificationConfig` — configure simplification per zoom.
- `geo_utils` — distance, projection and coordinate helpers.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
