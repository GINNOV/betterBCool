# FeverFrida / iThermonitor WT701 BLE protocol

Status: one physical FeverFrida/WT701 capture decoded. This document deliberately separates physical observations, corroborated interpretations, and remaining hypotheses.

## Device identity

The captured FeverFrida identifies itself through Device Information as model **WT701**, manufacturer **Raiing Medical Company**, firmware `02.20.17154`, hardware `02.46`, and software `1.1.5260`. This verifies the tested unit; other hardware revisions may differ.

## Published behavior

The following is documented by the WT701 manual and is not a BLE packet-level observation:

- axillary measurement range: 25–45 °C;
- one measurement every four seconds;
- measurements continue into local storage after a connection is lost;
- up to ten days of local measurements can be stored;
- reconnecting initiates upload of stored measurements;
- approximately 24 hours of stored measurements takes five minutes to upload;
- the receiver reports a low-battery condition;
- a short button press initiates or ends Bluetooth connection behavior;
- the original WT701 manual lists a CR2032 battery and a range up to five metres. Some later FeverFrida material may describe a different battery revision, so the physical unit wins.

Sources:

- WT701 manual: <https://usermanual.wiki/Raiing-Medical/701/html>
- FDA/NLM device record: <https://accessgudid.nlm.nih.gov/devices/06957324200156>
- FeverFrida archived FAQ: <https://images-na.ssl-images-amazon.com/images/I/81GiUJUhWyS.pdf>

## Advertisement map

| Field | Observed value | Confidence |
| --- | --- | --- |
| Local name | absent | verified |
| Service UUIDs | `FEE7` | verified |
| Manufacturer data | 29 bytes; includes battery-like `64`, a changing LE counter, and the ASCII device serial | observed; field meanings partly hypothesis |
| Service data | UUID `0397`, 20-byte stable value in this short run | verified bytes; meaning unknown |
| Connectable | true | verified |
| Advertising cadence | duplicate callbacks observed around 0.5–1 s; not a radio-level interval measurement | observed |

## GATT map

The physical unit exposed eight primary services. It did **not** expose standard Health Thermometer (`1809`) or Battery (`180F`) services. The machine-readable redacted map is in `Captures/2026-08-03-WT701/gatt.json`.

| Service | Characteristic | Properties | Descriptors | Meaning | Confidence |
| --- | --- | --- | --- | --- | --- |
| `180A` | `2A23`, `2A24`, `2A25`, `2A26`, `2A27`, `2A28`, `2A29`, `2A2A`, `2A50` | read | — | Device Information | verified |
| `70436BE4…6132` | `71D0523C…F8AC`, `7BF6AF4E…E5D0`, `03F1BEC7…39F8`, `071D5DB8…49BC` | see capture | CCCD on first two | unknown/session | verified map; meaning unknown |
| `A72435C3…A64C` | `5869CF77…30A1` | read, indicate | CCCD | direct realtime temperature + battery frame | corroborated |
| `A8740486…A950` | `DB765158…EAE9`, `E9A2825D…36E6`, `874A9717…D12D` | see capture | CCCD on first two | unknown | verified map; meaning unknown |
| `4393AFA6…6AAC` | `46B17614…6AAC`, `48CC12F4…E45D`, `DEFDC94E…E45D` | see capture | — | unknown | verified map; meaning unknown |
| `9869C505…1A3A` | `A44D0105…1A3A`, `953FDB2B…FF5F`, `D717EA19…1A3A`, `E7D6818F…1A3A` | read, write | — | unknown | verified map; meaning unknown |
| `42F65AE6…7BEF` | `B857035D…1757`, `5E119BB0…9A66`, `BF7A1506…D423` | see capture | CCCD on first | unknown | verified map; meaning unknown |
| `30D2A3E8…F84B` | `5B8604BE…B62D`, `028C3D3A…E385`, `F09AA8BE…0EEA`, `29A59C78…E45D` | see capture | CCCD on first and last | control/unknown; last is battery | battery corroborated; other meanings unknown |

### Static evidence used for interpretation

An archived Raiing application was inspected statically and never installed or executed. Its checksum did not match the mirror's advertised checksum, so it is treated only as untrusted corroborating evidence. Its WT701 handler names the physically observed realtime UUID and parses the exact frame layout below.

- `0000FFF0-0000-1000-8000-00805F9B34FB`, with `FFF1` and `FFF2` characteristics;
- services based at `5FC41000`, `5FC43000`, `5FC44000`, and `5FC45000`, with `01`/`02` characteristic variants;
- `F000CCC0-0451-4000-B000-000000000000`, with `CCC1`, `CCC2`, and `CCC3` variants.

Earlier UUID-family leads (`FFF0`, `5FC4…`, and `F000CCC0…`) were **not** present in this unit's GATT map.

## Direct realtime frame

Characteristic: `5869CF77-A8EA-47D8-A239-CD2100FA30A1` (read + indicate). Byte order is little-endian for every multibyte field.

| Offset | Size | Field | Interpretation | Confidence |
| --- | ---: | --- | --- | --- |
| 0 | 4 | device counter | seconds since an unresolved device/session origin | verified unit and monotonic behavior; origin unknown |
| 4 | 1 | battery | percent, 0–100 | corroborated |
| 5 | 2 | primary sensor | signedness not needed in device range; value / 1000 = °C | corroborated |
| 7 | 2 | secondary sensor | value / 1000 = °C | corroborated |
| 9 | 2 | reserved | captured as zero; original app ignores it | observed |
| 11 | 2 | checksum | CRC-16/CCITT-FALSE over bytes 0–10, LE on wire | corroborated and verified against capture |

Captured frame `A1 03 00 00 64 46 75 C9 7A 00 00 BF 6A` decodes to counter `929`, battery `100%`, primary `30.022 °C`, secondary `31.433 °C`, reserved `0`, checksum `0x6ABF`.

The original software applies a proprietary compensation algorithm to the two channels. Therefore the Swift package exposes both raw channels and uses the primary channel for its generic temperature stream; it does **not** label either as processed body temperature. A controlled ten-frame sequence is preserved in `Captures/2026-08-03-WT701/packets-warming.jsonl`.

## Battery

Battery is present both at byte 4 of the validated realtime frame and as a one-byte value on `29A59C78-CCC0-11E2-B493-14CF921AE45D`. Both captured values were `0x64` (100%).

## Remaining unknowns

History synchronization, clock/session control, the counter's origin, and the proprietary compensated body-temperature algorithm remain unresolved. This firmware did not emit attributable unsolicited indications after CCCD subscription in three controlled runs. `FeverFridaCentral` therefore keeps indications enabled but also reads the same realtime value every four seconds as a read-only streaming fallback. Requested reads are explicitly tracked so CoreBluetooth callbacks are not mislabeled merely because the characteristic is subscribed.

`FeverFridaKit` decodes the observed WT701 frame only when its UUID, exact length, battery range, and CRC all validate. It also retains support for Bluetooth SIG Temperature Measurement (`2A1C`), Intermediate Temperature (`2A1E`), and Battery Level (`2A19`) for other revisions.

The standard temperature decoder handles Celsius/Fahrenheit, IEEE-11073 32-bit FLOAT, and the optional timestamp and temperature-type fields. The standard battery decoder accepts the specified one-octet range of 0–100 percent.

Further interpretation should be tested against:

1. at least three stable temperatures spanning several degrees;
2. a reference thermometer and the app display at the same timestamps;
3. both byte orders and common scales (integer hundredths, tenths, IEEE-11073 FLOAT);
4. notification timing near the documented four-second live sampling interval;
5. reconnect behavior after at least several minutes offline, to separate live samples from history upload;
6. a fresh and depleted battery, if battery state is not exposed through standard Battery Service.

## Evidence rules

- `verified`: directly observed on physical FeverFrida hardware and present in a committed capture;
- `corroborated`: supported by physical capture plus an independent source or original-app static analysis;
- `hypothesis`: fits available bytes but lacks a controlled test;
- `unverified`: no target-hardware evidence.

Packet logs should use uppercase, space-delimited hex and ISO-8601 timestamps. Preserve unknown bytes exactly.
