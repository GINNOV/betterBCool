# betterBCool

betterBCool is an independent SwiftUI client experiment for Bosch Climate Series air conditioners managed through HomeCom Easy.

The app runs on iOS and supports both classic PointT RAC gateways and newer HomeCom/Matter RAC units using Bosch's Bacon MQTT device-shadow service. It still starts safely in demo mode until the owner completes Bosch SingleKey sign-in.

This project is not affiliated with or endorsed by Bosch.

## What works

- Native SwiftUI dashboard for iPhone and iPad
- Power, room temperature, temperature setpoint, operating mode, and fan-state display
- Parsing of the supplied HomeCom RAC base telemetry export
- Typed climate state and capability models
- Read-only historical/demo data service
- A transport-level PointT client for gateway discovery and individual resource reads/writes
- Bacon device discovery and native MQTT 5 over WebSocket shadow reads/writes
- Validation of temperature ranges, increments, modes, and fan speeds before writes

The displayed telemetry currently agrees with the data observed by the device owner. This confirms the state model and UI mapping; it does not by itself confirm that every Bosch model exposes the same capabilities.

## Project status

The iOS app builds and runs. It defaults to `DemoClimateService`, so launching the repository as supplied does not contact Bosch or change an AC setting. In Settings, **Sign in with Bosch** opens the SingleKey ID browser flow, exchanges the callback using OAuth 2.0 with PKCE, discovers either a PointT or Bacon RAC, validates a live read, and then enables live access.

The verified cloud path for the owner's newer HomeCom unit is:

- Bosch SingleKey ID OAuth2 authentication
- Bacon claiming discovery in the EU region
- MQTT 5 over a TLS WebSocket
- Per-device desired/reported state shadows

The live adapters support power, mode, fan, setpoint, and swing writes followed by a fresh authoritative read. Access and refresh tokens are stored in the iOS Keychain, refreshed automatically before expiry, and removed on sign-out. The newer shadow does not report ambient room temperature, so the live UI shows it as unavailable rather than substituting the setpoint.

## Requirements

- macOS with Xcode 26 or newer
- iOS 17 or newer deployment target
- Swift 5.9 or newer

## Run the app

1. Open `BetterBCoolApp.xcodeproj` in Xcode.
2. Select the `BetterBCool` scheme.
3. Choose an iOS Simulator or a configured iPhone.
4. Press Run.

No Bosch credentials are required for the bundled read-only demo.

## Run the tests

From the repository root:

```sh
swift test
```

The tests cover sanitized telemetry, state validation, PointT requests, Bacon claiming requests, MQTT 5 packet encoding/decoding, JWT subject extraction, and verified shadow mapping. Network tests use interceptors and do not send requests to Bosch. Raw household telemetry exports remain local and are ignored by Git.

## Architecture

```text
BetterBCoolApp
    └── BetterBCoolUI
            └── ClimateViewModel
                    └── ClimateService
                            ├── DemoClimateService
                            ├── ReadOnlyHistoricalService
                            ├── PointTClimateService
                            │       └── PointTAPI
                            └── BaconClimateService
                                    ├── BaconAPI
                                    └── BaconMQTTClient
```

## Reliable cloud scheduling

The optional companion service in [`backend`](backend/) runs routines through Vercel Workflow. When enabled in Settings, schedules continue while the iPhone is suspended or offline, delayed steps survive deployments, and transient Bosch requests retry automatically. Neon stores schedule metadata and application-encrypted OAuth tokens.

The direct on-device connection remains available when cloud scheduling is disabled.

- `BetterBCoolCore` contains domain models, validation, service boundaries, and the PointT and Bacon transports.
- `BetterBCoolUI` contains the dashboard and its view model.
- `App` is the iOS composition root and selects demo, PointT, or Bacon based on verified discovery.

## Evidence and documentation

- [Protocol findings](docs/protocol-findings.md)
- [Next capture checklist](docs/next-capture.md)
- [Safety and legal boundaries](docs/safety-and-legal.md)

The local artifacts establish the telemetry surface but do not contain an original HomeCom request capture. Externally documented endpoints are therefore treated as implementation leads until confirmed against an authorized, sanitized session from the owner's account.

## Safety and privacy

Use betterBCool only with accounts and equipment you own or are explicitly authorized to administer.

- Never commit access tokens, refresh tokens, cookies, passwords, certificates, serial numbers, MAC addresses, or location data.
- Keep live writes disabled until the device's reported capabilities and response semantics are confirmed.
- Test one reversible property at a time and re-read authoritative state after every command.
- Do not expose diagnostic compressor or electrical telemetry as writable controls.
- Keep the official HomeCom Easy app available as a recovery path.

## Contributing

Useful contributions include sanitized request/response schemas, additional telemetry fixtures with identifying information removed, model-specific capability observations, tests, and accessibility improvements.

When reporting protocol behavior, distinguish clearly between:

1. behavior observed from an owned device,
2. behavior inferred from third-party source code, and
3. behavior that remains hypothetical.

## License

Copyright 2026 betterBCool contributors.

The original source code in this repository is licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution and trademark information.

Apache-2.0 applies to betterBCool's code; it does not grant rights to Bosch services, APIs, firmware, product names, or trademarks. Third-party components and referenced projects remain subject to their own licenses.
