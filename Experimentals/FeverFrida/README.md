# FeverFrida / iThermonitor WT701 BLE Research

`Experimentals/FeverFrida` is an exploratory research component within **betterBCool**. It contains the protocol decoder library, test fixtures, and CoreBluetooth tools developed to communicate with the **Raiing Medical WT701** (sold commercially as *FeverFrida / iThermonitor*) continuous BLE body-temperature sensor.

This work is maintained as an isolated research module for protocol discovery and experimental thermal telemetry inputs.

---

## Directory Structure

```text
Experimentals/FeverFrida/
├── Sources/
│   └── FeverFridaKit/          # Core Swift decoder & CoreBluetooth models
│       ├── Decoders/           # Realtime frame, advertisement & packet decoders
│       ├── Models/             # Device state, temperature reading, and session structures
│       └── Protocol/           # GATT service & characteristic UUID definitions
├── Examples/
│   └── FeverFridaExplorer/     # Standalone SwiftUI/CoreBluetooth diagnostic app
├── Tests/
│   └── FeverFridaKitTests/     # Unit tests and deterministic byte-stream fixtures
└── docs/
    ├── feverfrida-protocol.md  # GATT map, packet structure, and checksum analysis
    ├── feverfrida-capture.md   # Packet capture guidance and sanitization rules
    └── next-capture.md         # Capture session checklist and next steps
```

---

## Components

### 1. `FeverFridaKit`
The core Swift library target defined in `Package.swift`. It provides:
- **GATT & Advertisement Parsing**: Extracts the 29-byte manufacturer data, service UUIDs (`FEE7`), and device serial from BLE advertisement packets.
- **Real-Time Frame Decoder**: Decodes the 10-byte indication packet on characteristic `5869CF77…30A1`:
  - Packet header (`0xAA`)
  - Sequence counter
  - Dual 16-bit temperature words (`temp1`, `temp2` / calibration delta)
  - Battery status indicator
  - Modulo-256 byte-sum verification
- **Connection Lifecycle Management**: Connects without requiring vendor cloud auth or proprietary pairing handshakes.

### 2. `FeverFridaExplorer`
A lightweight, standalone SwiftUI example application located in `Examples/FeverFridaExplorer/`. It provides a live diagnostic UI to:
- Scan for nearby WT701 peripherals;
- Display live signal strength (RSSI), battery level, and firmware revisions;
- Stream calibrated temperature readings in real time;
- Log raw GATT characteristics for protocol verification.

### 3. `FeverFridaKitTests`
Deterministic unit tests covering:
- Valid and corrupted frame decoding;
- Checksum validation and out-of-range temperature handling;
- Advertisement packet slicing and serial number extraction;
- Offline historical replay fixtures.

---

## Documentation & Protocol Reference

Detailed protocol notes and reverse-engineering findings are documented in the `docs/` folder:

| Document | Description |
|---|---|
| [**`docs/feverfrida-protocol.md`**](docs/feverfrida-protocol.md) | Full GATT service map (8 primary services), 10-byte packet layout, raw byte descriptions, and static corroboration notes. |
| [**`docs/feverfrida-capture.md`**](docs/feverfrida-capture.md) | Step-by-step instructions for capturing BLE traffic with PacketLogger / Wireshark and sanitizing sensitive serial numbers before export. |
| [**`docs/next-capture.md`**](docs/next-capture.md) | Checklist of unmapped characteristics and verification targets for future hardware capture sessions. |

---

## Testing & Development

Run the test suite using Swift Package Manager:

```sh
# Run only FeverFrida tests
swift test --filter FeverFridaKitTests

# Run all betterBCool package tests
swift test
```

All tests execute against deterministic synthetic byte fixtures and do not require physical BLE hardware.

---

## Safety & Boundaries

- **Not for Medical Use**: This software is intended strictly for protocol research and personal ambient comfort automation (e.g. automating room air conditioning thresholds). It is not a medical device and must not be used for diagnostic, monitoring, or medical purposes.
- **Privacy & Sanitization**: Raw hardware captures contain device serial numbers and physical environment data. Raw capture files must never be committed to source control; only sanitized, anonymized fixtures belong in this repository.
