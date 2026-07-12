# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog] and this project adheres to [SemVer].

## [Unreleased]

### Changed

- Renamed internal v7.0.0 implementations to canonical names: `route_manager_new.dart` → `route_manager.dart`,
  `new_search_rect.dart` (`SearchRectBuffer`) → `search_rect.dart`. The legacy `SearchRect` became `OldSearchRect` (
  `old_search_rect.dart`). No public API change.
- Translated all code and API doc comments to English.
- Switched the lint preset from `static_analyze_av` to `very_good_analysis` and fixed the resulting warnings.

### Removed

- Dead legacy route-manager code (old `route_manager.dart`, `route_manager_basic.dart`, `copy_policy.dart`,
  `old_side_point.dart`).

## [7.0.0]

Versions before 7.0.0 were tracked only as branch names, not tags, and are not listed here. 7.0.0 is the first release
tracked in this changelog.

### Added

- Two-layer architecture: `RouteDataEngine` (owns data + persistence) and `RouteManager` (pure navigation computer).
- Structure-of-arrays / flat `Float64List` buffers for route geometry, search rectangles and side points.
- DTO transfer protocol (`RMConfig`, `RMState`, `RouteProgress`) with zero-copy cross-isolate transfer via
  `TransferableTypedData`.
- Custom binary serialization (`BinaryWriter` / `BinaryReader`) with atomic, non-blocking dump writes.

### Changed

- Renamed the package from `geo_utils` to `navigation_lib`; consumers must update imports to
  `package:navigation_lib/navigation_lib.dart`.

### Removed

- Unused `geolocator` and `cupertino_icons` dependencies.

[unreleased]: https://github.com/Good-rice-soup/navigation_lib/compare/v7.0.0...HEAD

[7.0.0]: https://github.com/Good-rice-soup/navigation_lib/releases/tag/v7.0.0

[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/

[SemVer]: https://semver.org
