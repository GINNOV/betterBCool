# betterBCool

betterBCool is an independent SwiftUI client experiment for Bosch Climate Series air conditioners managed through HomeCom Easy.

The app is running on iOS and the values displayed by the current dashboard have been checked against the owner's observed AC data. The project is still deliberately conservative: its bundled configuration uses verified historical/demo telemetry, while live authentication and control remain isolated behind service interfaces until they can be validated safely.

This project is not affiliated with or endorsed by Bosch.

## What works

- Native SwiftUI dashboard for iPhone and iPad
- Power, room temperature, temperature setpoint, operating mode, and fan-state display
- Parsing of the supplied HomeCom RAC base telemetry export
- Typed climate state and capability models
- Read-only historical/demo data service
- A transport-level PointT client for gateway discovery and individual resource reads/writes
- Validation of temperature ranges, increments, modes, and fan speeds before writes

The displayed telemetry currently agrees with the data observed by the device owner. This confirms the state model and UI mapping; it does not by itself confirm that every Bosch model exposes the same capabilities.

## Project status

The iOS app builds and runs. It defaults to `DemoClimateService`, so launching the repository as supplied does not contact Bosch or change an AC setting. The in-app Settings panel can switch to live PointT read/write access after an access token and gateway ID are supplied; the token is stored in the iOS Keychain.

The likely cloud interface for this gateway family is:

- Bosch SingleKey ID OAuth2 authentication
- PointT gateway discovery
- REST resources below `airConditioning`

The live adapter reads individual resources and supports power, mode, fan, setpoint, and swing writes followed by a state refresh. An integrated SingleKey browser login and automatic token refresh are still future work, so the current live configuration requires an owner-obtained access token.

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

The tests cover sanitized telemetry samples, state validation, PointT gateway request construction, bearer authorization headers, and isolated setpoint write envelopes. Network tests use an interceptor and do not send requests to Bosch. Raw household telemetry exports remain local and are ignored by Git.

## Architecture

```text
BetterBCoolApp
    └── BetterBCoolUI
            └── ClimateViewModel
                    └── ClimateService
                            ├── DemoClimateService
                            ├── ReadOnlyHistoricalService
                            └── future verified live service
                                    └── PointTAPI
```

- `BetterBCoolCore` contains domain models, CSV import, capability validation, service boundaries, and the low-level PointT transport.
- `BetterBCoolUI` contains the dashboard and its view model.
- `App` is the iOS composition root and currently selects the safe demo service.

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

No project license has been selected yet. Until one is added, normal copyright restrictions apply to the original source code in this repository. Third-party names and components remain subject to their respective owners and licenses.
