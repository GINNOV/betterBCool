# betterBCool

betterBCool is an independent SwiftUI climate-control app for Bosch Climate Series air conditioners managed through HomeCom Easy. It includes an iPhone app, an Apple Watch companion, and an optional Vercel/Neon service for routines that should continue while the iPhone is offline.

The app is designed to be safe to explore: a fresh build starts in an interactive local demo and does not contact Bosch or change a real unit until the owner completes Bosch SingleKey sign-in.

> betterBCool is not affiliated with, endorsed by, or sponsored by Bosch.

## What the app does

### iPhone

- Shows power, room temperature when reported, setpoint, operating mode, fan state, and available comfort features.
- Changes power, temperature, mode, fan speed, Eco, Sleep, and horizontal/vertical swing settings.
- Validates every requested value against the selected transport's capabilities before sending it.
- Re-reads authoritative device state after a live change and keeps a local activity log of confirmed changes.
- Creates recurring routines made from timed climate steps.
- Reads nightly Apple Watch wrist-temperature samples from Apple Health, calculates a personal baseline, and can optionally turn cooling on when a fresh sample is above that baseline.
- Keeps Bosch access and refresh tokens in the iOS Keychain.

### Apple Watch

The Watch is a quick-control surface for the paired iPhone. It can:

- Display the current unit and whether it is connected or read-only.
- Turn the unit on or off.
- Adjust the setpoint with the Digital Crown using the unit's supported range and increment.
- Turn all saved routines on or off together.
- Refresh the latest climate snapshot.

The Watch does not sign in to Bosch and does not store Bosch credentials. It sends a narrow, user-initiated request through WatchConnectivity; the iPhone performs the authenticated read or write and sends a snapshot back.

## How it works

```text
Apple Watch
    │  WatchConnectivity: request / snapshot
    ▼
iPhone app ── local mode ──► DemoClimateService
    │
    ├─ direct mode ─────────► Bosch SingleKey → PointT REST or Bacon MQTT
    │
    └─ cloud mode ──────────► betterBCool Cloud → Bosch PointT or Bacon
                               │
                               └─ durable scheduled routines
```

The iPhone is the normal composition root. It selects one climate service after sign-in and exposes that service to the dashboard, routines, Watch requests, and optional cloud scheduler.

### First launch and sign-in

1. The app opens with the interactive **Living Room** demo. Demo changes stay in memory and never reach Bosch.
2. **Settings → Sign in with Bosch** opens the Bosch SingleKey ID browser flow.
3. betterBCool receives the OAuth callback using PKCE. The app does not see or store the Bosch password.
4. The fresh access token is used to discover a compatible device and verify a live read before the session is enabled.
5. The app stores the token pair in Keychain and remembers the discovered device and transport. Tokens are refreshed before expiry.

The current discovery flow selects the first compatible air conditioner returned for the signed-in account. Multi-unit selection is not yet exposed in the UI.

### iPhone dashboard

The dashboard is organized around the controls most often needed at home:

- **Power** in the header.
- **Temperature** with half-degree adjustments where supported.
- **Mode**: Auto, Cool, Dry, Fan, and Heat when exposed by the service.
- **Fan**: Auto, Quiet, Low, Medium, High, and Turbo when supported. Dry mode may manage the fan automatically.
- **Comfort**: Eco, Sleep, vertical swing, and horizontal swing.
- **Schedules** for recurring routines.
- **Wrist temperature** when Apple Health has a usable sample.
- **Activity** for the latest confirmed unit changes. The log is local, capped at 50 entries, and can be cleared without changing the unit.

The UI updates immediately after a valid tap, then reconciles with the device response. If the write fails, the previous state is restored and the dashboard reports the failure.

### Apple Watch request flow

The Watch keeps the latest `WatchSnapshot` in its application context so it can render a useful screen when the iPhone is not immediately reachable.

- When the iPhone is reachable, a request receives a direct reply and the Watch displays the returned state.
- When the iPhone is temporarily unreachable, the request is queued with WatchConnectivity for delivery when connectivity returns. The Watch shows that the iPhone must be opened to apply the change.
- If Bosch authentication has expired, the Watch asks the owner to reconnect Bosch on the iPhone.
- If the selected device is unavailable or does not support a requested value, the Watch keeps the error local and does not bypass the iPhone's validation.

The Watch can toggle the saved routines as a group, but routine creation and step editing remain on the iPhone.

## Live Bosch transports

The app uses a transport-neutral `ClimateService` boundary. After discovery, the selected adapter is:

| Device family | Transport | State and writes |
| --- | --- | --- |
| Classic PointT RAC gateways | Bosch PointT REST API | Reads individual resources and writes supported power, mode, fan, setpoint, Eco, Sleep, and swing values. Room temperature is available when the gateway reports it. |
| Newer HomeCom/Matter RAC units | Bacon MQTT 5 over a TLS WebSocket | Reads and updates the per-device reported/desired shadow. Ambient room temperature is shown as unavailable when the shadow does not report it. |

Both adapters validate ranges, supported modes/fan speeds, and half-degree setpoint increments before writing. Live writes are followed by a fresh read. Device capabilities can vary by model, so the UI may disable a control even when the common climate model contains it.

## Routines and scheduling

A routine has:

- a name and start time,
- selected weekdays,
- one or more climate steps,
- an optional duration for each step except the final step, which remains active until the next transition.

The editor includes a **Night comfort** template that cools down, becomes quiet, pauses, and resumes silently. Every step can be changed before saving.

There are two scheduling modes:

| Mode | Behavior |
| --- | --- |
| **On-device scheduling** | Routines are stored privately on the iPhone and run while betterBCool is active. Missed changes are not replayed when the app is opened later. |
| **Cloud scheduling** | Routines are synchronized to the optional backend. Vercel Workflow provides durable waits, revision checks, and retries while the iPhone is suspended or offline. |

When cloud scheduling is enabled, manual climate commands also go through the backend so the phone and server do not race to refresh the same Bosch token. Cloud credentials are encrypted at the application layer before being stored in Neon.

See [`backend/README.md`](backend/README.md) for deployment and environment-variable instructions.

## Apple Health and wrist-temperature cooling

Apple Watch does not provide a continuous live body-temperature stream to third-party apps. Supported Apple Watch sleep tracking produces an aggregate `appleSleepingWristTemperature` sample, normally associated with Sleep Focus.

When the owner grants read access in **Settings → Apple Watch cooling**, betterBCool:

1. monitors Apple Health for new wrist-temperature samples;
2. displays the latest sample and the average of prior samples as a personal baseline;
3. considers a sample fresh for up to 18 hours;
4. requires at least three prior samples before using the baseline for automation;
5. can turn cooling on when the fresh sample is at least the configured threshold above the baseline.

This is a comfort automation, not real-time temperature control and not a medical feature. The app requests read-only HealthKit access; it does not write health data.

## Project status and limitations

The iPhone app, Watch companion, live PointT path, live Bacon path, cloud scheduler, and protocol tests are under active development. The implementation is based on behavior observed from authorized devices and sanitized exports. A successful read on one Bosch model does not prove that every HomeCom model exposes the same fields or accepts the same writes.

Current limitations include:

- one discovered air conditioner is selected per signed-in installation;
- the Watch offers quick controls, not the full iPhone dashboard;
- Bacon shadows may not provide ambient room temperature;
- local routines require the app to remain active;
- cloud scheduling requires deploying and configuring the companion backend;
- the official HomeCom Easy app should remain available as a recovery path.

## Requirements

- macOS with Xcode 26 or newer;
- iOS 17 or newer;
- watchOS 10 or newer for the Watch target;
- Swift 5.9 or newer;
- an Apple Watch paired with the test iPhone for Watch and wrist-temperature features;
- a Bosch HomeCom Easy account and an owned or authorized compatible unit for live access.

## Build and run

1. Open [`BetterBCoolApp.xcodeproj`](BetterBCoolApp.xcodeproj) in Xcode.
2. Select the `BetterBCool` scheme.
3. Choose an iOS Simulator or a configured iPhone and run.
4. For Watch development, select the embedded `BetterBCoolWatch` target on a paired Apple Watch.

No Bosch credentials are required for the bundled demo. To test live access, configure your own signing team and entitlements, install the app on an iPhone, complete Bosch sign-in, and keep the official app available for comparison and recovery.

Apple Health access is only meaningful on supported physical hardware. The UI test suite also includes a deterministic wrist-temperature preview so the dashboard can be tested without real HealthKit samples.

## Test

From the repository root:

```sh
swift test
```

The Swift tests cover:

- climate-state mapping and validation;
- PointT request construction and response parsing;
- Bacon device discovery, MQTT 5 packet encoding/decoding, and shadow mapping;
- OAuth and Keychain-related helpers;
- schedules and timeline calculations;
- Watch request/snapshot models;
- sanitized telemetry and FeverFrida protocol decoders.

The backend has its own checks:

```sh
cd backend
npm install
npm test
npm run typecheck
npm run build
```

Network-facing tests use interceptors or fixtures; they do not send test commands to Bosch.

## Repository layout

```text
App/                         iPhone composition root, settings, sign-in, WatchConnectivity bridge
Watch/                       Apple Watch app and its mirrored Codable transport models
Sources/BetterBCoolCore/     Climate models, validation, auth, schedules, and service adapters
Sources/BetterBCoolUI/       SwiftUI dashboard, view model, routines, and activity log
Sources/FeverFridaKit/       BLE telemetry and protocol decoding utilities
Examples/                    Small protocol exploration app
backend/                     Optional Vercel Workflow + Neon cloud scheduler
docs/                        Protocol notes, capture guidance, and safety boundaries
Tests/                       Swift unit tests and transport fixtures
UITests/                     iOS UI tests
```

Core service architecture:

```text
ClimateDashboard
    └── ClimateViewModel
            └── ClimateService
                    ├── DemoClimateService
                    ├── ReadOnlyHistoricalService
                    ├── PointTClimateService → PointTAPI
                    ├── BaconClimateService → BaconAPI + BaconMQTTClient
                    └── CloudClimateService → betterBCool Cloud
```

## Evidence and documentation

- [Protocol findings](docs/protocol-findings.md)
- [FeverFrida protocol notes](docs/feverfrida-protocol.md)
- [Capture guidance](docs/feverfrida-capture.md)
- [Next capture checklist](docs/next-capture.md)
- [Safety, privacy, and legal boundaries](docs/safety-and-legal.md)
- [Changelog](CHANGELOG.md)

When documenting protocol behavior, distinguish between behavior observed from an owned device, behavior inferred from third-party source code, and behavior that remains hypothetical.

## Safety and privacy

Use betterBCool only with accounts and equipment you own or are explicitly authorized to administer. Do not bypass access controls, certificate pinning, multi-factor authentication, account limits, or ownership checks.

Never commit access tokens, refresh tokens, cookies, passwords, client secrets, certificates, serial numbers, MAC addresses, precise locations, or household telemetry. Keep live writes supervised, reversible, and within values accepted by the official app. Do not expose diagnostic compressor or electrical telemetry as writable controls.

## Contributing

Useful contributions include sanitized request/response schemas, additional model-specific capability observations, protocol fixtures with identifying information removed, tests, accessibility improvements, and documentation.

Please include the device family and transport when reporting behavior, and remove all account and household identifiers from captures before sharing them.

## License

Copyright 2026 betterBCool contributors.

The original source code in this repository is licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution and trademark information.

Apache-2.0 applies to betterBCool's code; it does not grant rights to Bosch services, APIs, firmware, product names, or trademarks. Third-party components and referenced projects remain subject to their own licenses.
