# Changelog

Notable changes to betterBCool are documented here.

The project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-07-22

### Added

- Made demo mode interactive so power, mode, fan, temperature, and swing controls can be explored without a live account.
- Added a clearer fan-speed display with a current-speed label and visual intensity bars.

### Changed

- Made climate controls update optimistically, providing immediate visual feedback while device requests complete in the background.
- Enabled half-degree temperature changes for both direct Bacon and cloud-backed connections.
- Moved the Settings button into the scrolling dashboard header so it no longer floats over content.
- Improved missing room-temperature presentation to explain when a device does not report an ambient reading.

## [0.1.0] - 2026-07-22

### Added

- Added live HomeCom control for PointT and newer Bacon/Matter air conditioners, including power, mode, fan, setpoint, and swing commands.
- Added local and cloud-backed climate schedules, including recurring routines and remote execution while the iPhone is offline.
- Added Bosch SingleKey sign-in with PKCE, secure Keychain token storage, automatic refresh, and gateway discovery.
- Added the original SwiftUI climate dashboard, telemetry import, verified PointT resource client, generated app artwork, Apache 2.0 licensing, and automated tests.

[Unreleased]: https://github.com/GINNOV/betterBCool/compare/v1.0...HEAD
[1.0.0]: https://github.com/GINNOV/betterBCool/compare/01fda3a0c313e9f16956ae710053c7d77b01d4ef...v1.0
[0.1.0]: https://github.com/GINNOV/betterBCool/commits/01fda3a0c313e9f16956ae710053c7d77b01d4ef
