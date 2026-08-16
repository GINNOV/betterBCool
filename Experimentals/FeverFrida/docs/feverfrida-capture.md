# FeverFrida capture procedure

The `FeverFridaKit` target contains a protocol-neutral CoreBluetooth explorer. The Xcode project also contains a dedicated iOS app named **FeverFridaExplorer**. It scans without a service filter, captures all advertisement fields exposed by Apple platforms, enumerates the complete GATT hierarchy, reads characteristics marked readable, reads descriptors, and enables every notify/indicate characteristic.

## Required setup

1. Use an iPhone or iPad; the iOS Simulator cannot capture nearby BLE peripherals.
2. In Xcode, select the `FeverFridaExplorer` scheme and a connected iPhone or iPad. Its Bluetooth permission text is already configured.
3. Insert a known-good battery and record the battery model printed on the FeverFrida unit.
4. Keep the original iThermonitor app closed so it does not take the connection.
5. Start the explorer before powering on the sensor, so the first advertisements are not missed.

Every app launch creates a timestamped folder under `FeverFridaCaptures` in the app's Documents directory. Advertisement and packet records are appended immediately, while `gatt.json` is replaced as discovery fills in characteristics and descriptors. The files therefore survive app termination and are visible through iOS file sharing in addition to the app's share buttons.

The picker hides advertisements that identify themselves with Apple's Bluetooth company identifier (`0x004C`) or a recognizable Apple product name. They remain in the raw advertisement log so the evidence is complete and the filter cannot erase a mistakenly classified packet.

Do not treat a map as complete unless its `isComplete` field is `true`. The export includes primary/secondary status, included services, characteristics, properties, latest readable values, descriptors, descriptor values, and any discovery errors.

## Swift API shape

The capture app uses the same public API available to any iOS host:

```swift
let sensor = FeverFridaCentral()
try await sensor.waitUntilReady()

for await advertisement in try sensor.scan() {
    // Choose the physical sensor after correlating name, RSSI, and timing.
    try await sensor.connect(to: advertisement.id)
    break
}

async let temperatures: Void = {
    for await sample in sensor.temperatureStream() {
        print(sample.celsius)
    }
}()

async let battery: Void = {
    for await level in sensor.batteryStream() {
        print(level.percent)
    }
}()
```

The typed streams emit for Bluetooth SIG standard characteristics and for checksum-valid WT701 realtime/battery frames. `wt701FrameStream()` exposes both raw temperature channels and the device counter. Use `packetStream()` and JSONL export to retain every proprietary characteristic.

## Advertisement capture

1. Begin an unfiltered scan with duplicate advertisements enabled.
2. Long-press the sensor button to power it on.
3. Capture at least 60 seconds while disconnected.
4. Short-press once and capture another 30 seconds.
5. Export `advertisements.jsonl`.
6. Record which visible LED pattern occurred during each interval.

Do not identify the sensor by name alone. Compare its first-seen time, RSSI changes when moved near the phone, service UUIDs, and manufacturer/service data.

## GATT and notification capture

1. Connect to the CoreBluetooth peripheral identifier selected from the advertisement capture.
2. Wait until all services, characteristics, and descriptors appear.
3. Export `gatt.json`.
4. Leave the sensor untouched for at least 60 seconds and export `packets.jsonl`.
5. Hold the probe between fingers or against a warm reference surface for two minutes, recording reference temperatures and timestamps.
6. Remove it and continue for two minutes.
7. Export a second packet log.

## History-versus-live experiment

1. Disconnect the phone for at least ten minutes while leaving the sensor on.
2. Reconnect and capture until notification traffic returns to its steady cadence.
3. A burst substantially faster than one sample every four seconds is a history-transfer candidate, not a live-temperature format by itself.

## File naming

Use one immutable directory per run:

```text
Captures/YYYY-MM-DD-device-label/
  metadata.md
  advertisements.jsonl
  gatt.json
  packets-baseline.jsonl
  packets-warming.jsonl
  packets-reconnect.jsonl
```

Redact the phone's CoreBluetooth peripheral UUID before publishing if desired, but replace it consistently within a run. Do not alter payload bytes.
