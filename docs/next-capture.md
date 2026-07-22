# Next capture checklist

The blocker is missing request-level evidence. Produce a sanitized capture from an account and device you own.

## Preferred evidence

1. Record the official app version, iOS version, AC model, gateway hardware/firmware versions, and region.
2. Start a proxy capture using an owner-installed trust profile, if the app permits ordinary user-trusted TLS inspection.
3. Capture separate short sessions for login, device-list refresh, state refresh, and one control at a time: power, setpoint +0.5 °C, mode, fan, and swing.
4. Return each changed value to its original setting.
5. Export HAR or equivalent request/response logs, preserving timing and headers but redacting secrets.

Do not weaken or patch the app if it rejects interception. In that case, use vendor-provided diagnostics, DNS observations, and your own account's data export, or request an official integration from Bosch.

## Redaction

Replace values consistently so relationships remain visible:

- Tokens/cookies/authorization codes: `<TOKEN_1>`
- Email and user IDs: `<USER_1>`
- Home/device/serial/MAC identifiers: `<DEVICE_1>`
- Coordinates and addresses: `<LOCATION_1>`
- Certificate/private-key material: remove entirely

Keep URL paths, HTTP methods/statuses, non-secret header names, JSON field names/types, MQTT topic structure with identifier segments replaced, timestamps, and the before/after state payloads.

Pay particular attention to traffic involving SingleKey ID, `pointt-api.bosch-thermotechnology.com`, or an AWS IoT WebSocket endpoint. These are leads from independent implementations, not confirmed hosts for this device.

## Evidence matrix

For every action, capture the request, immediate response, subsequent state read/event, and visible result in the official app. This distinguishes command submission from acknowledgement and authoritative state.
