# Protocol findings

## Evidence inventory

Analyzed on 2026-07-22:

| Artifact | What it establishes | What it does not establish |
| --- | --- | --- |
| `Logs/RAC_BASE/*.csv` | Historical user-facing AC state at about 30-minute intervals | URLs, HTTP methods, MQTT topics, authentication, or write payloads |
| `Logs/RAC_EXTENDED/*.csv` | Historical engineering telemetry at about 30-minute intervals | A supported control interface |
| `opensourcecomponents.txt` | Gateway firmware includes AWS IoT, MQTT, HTTP, TLS, CBOR, JSON, and FreeRTOS components | Which transport HomeCom actually uses for each operation, or any broker/topic names |
| `device.txt` | User-supplied identification notes: Climate Series and gateway generation G10-3 | A verified model number, firmware version, serial number, or API host |

There are no HAR/PCAP files, proxy logs, app binaries, decrypted requests, screenshots, or Xcode sources in the current folder.

## Confirmed state surface

The base export exposes these fields:

- Power: `powerEnabled`
- Operating mode: observed `auto`, `cool`, `dry`, `fan`, `heat`
- Fan speed: observed `auto`, `low`, `medium`, `quiet`, and blank
- Setpoint: observed 15–32.5 °C in 0.5 °C increments, plus blank rows
- Room temperature: observed 15–32.5 °C in 0.5 °C increments
- Features: breeze-away, eco, full-power, horizontal swing, ionizer, setback, sleep, and vertical swing
- Timer-like values: `offTimestamp [sec]` and `onTimestamp [sec]`; only zero appears in the inspected data

The extended export contains compressor, coil, fan, voltage/current, and outdoor measurements. Treat these as diagnostic telemetry, not control inputs.

## Live account findings

An authorized SingleKey session on 2026-07-22 established the following without logging credentials or device identifiers:

- PointT gateway discovery returned HTTP 200 with the body `[]`.
- Bacon claiming discovery in `euc1` returned one owned device.
- MQTT 5 over the EU Bacon WebSocket broker connected successfully.
- A read-only device-shadow request returned 18 reported fields, including `powerEnabled`, `opMode`, `fanSpeed`, `tempSetpoint`, `hSwingEnabled`, and `vSwingEnabled`.
- The shadow did not include ambient room temperature.

The app therefore routes this account to the Bacon transport. PointT remains supported for classic gateways.

## Architecture evidence

The firmware component list makes an outbound TLS connection to AWS IoT plausible: it includes `aws-iot-sdk`, fleet provisioning, `coreMQTT-Agent`, and secure sockets. It also includes HTTP, JSON, and CBOR stacks. This supports a likely cloud-mediated architecture, but it does **not** reveal whether the mobile app uses REST, MQTT/WebSockets, or another Bosch backend, and it is not evidence of local-LAN control.

The supplied artifacts alone did not reveal endpoints or topics. The read-only live verification above and the current `homecom_alt` implementation supplied the Bacon claiming and device-shadow contract used by the Swift adapter.

## External implementation leads

These are useful capture targets, not facts proven by the local artifacts:

- Bosch's public HomeCom pages confirm remote temperature/mode control and show the Climate family as supported, but do not publish a HomeCom developer API: <https://www.bosch-homecomfort.com/it/it/residenziale/assistenza-e-servizi/app/homecom-easy/>.
- The third-party `homecom_alt` package reports SingleKey ID OAuth2 plus a REST service at `pointt-api.bosch-thermotechnology.com` for conventional RAC gateways. Its documentation separately describes a newer Matter-commissioned AC path using an AWS-IoT-style MQTT 5 device shadow: <https://pypi.org/project/homecom_alt/>.
- An independent 2022 API note reports `GET /pointt-api/api/v1/gateways/`, reads below `/gateways/{id}/resource/airConditioning/`, and `PUT` writes to individual resources: <https://gist.github.com/neugartf/364e3a05b03ab8044bb15f8f2bf6e493>.

The supplied identifier prefix was not a reliable transport discriminator: live discovery proved this account uses Bacon despite differing from the example prefix documented by `homecom_alt`.

Do not substitute Bosch Smart Home's documented local API: that is a different product family and there is no evidence the G10-3 gateway exposes it.

## Candidate API surface

Once captured, the minimum independent client likely needs these logical operations (names intentionally transport-neutral):

1. Authenticate interactively using the vendor-supported browser flow and securely refresh tokens.
2. List homes/locations and discover owned devices.
3. Read device metadata, capabilities, availability, and current state.
4. Apply a partial state change for power, mode, setpoint, fan, or a supported feature.
5. Observe acknowledgement and then refresh authoritative state.

The Swift core expresses this as `ClimateService`; a future adapter should translate these operations only after the exact contract is observed.

## Guardrails for a future write adapter

- Derive ranges and supported modes from device capabilities when available; do not assume the historical extrema are universal limits.
- Send one changed property at a time during initial validation.
- Require an explicit user action for every write; do not add schedules or background automation initially.
- Rate-limit writes, reject non-finite temperatures, and re-read state after acknowledgement.
- Never expose extended engineering fields as writable values.
