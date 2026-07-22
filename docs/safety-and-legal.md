# Safety, privacy, and legal boundaries

This project should interoperate only with devices and accounts the tester owns or is explicitly authorized to administer.

- Do not bypass access controls, certificate pinning, multi-factor authentication, account limits, or device ownership checks.
- Prefer documented export/debug facilities and a proxy installed and trusted by the owner on the owner's phone. Do not intercept anyone else's traffic.
- Do not extract, publish, or commit passwords, access/refresh tokens, cookies, client secrets, certificates, serial numbers, MAC addresses, precise locations, or household telemetry.
- Respect Bosch terms, applicable copyright/interoperability exceptions, computer-misuse laws, privacy law, and radio/electrical safety rules in the relevant jurisdiction. This repository is not legal advice.
- Avoid firmware modification, safety-controller access, factory endpoints, or commands affecting compressor protection. AC control can affect equipment, occupants, pets, and buildings.
- Keep the official app available as a recovery path. Initial tests should be supervised, reversible, rate-limited, and within values already accepted by the official UI.

Responsible disclosure is appropriate if analysis reveals a vulnerability. Do not publish exploitable credentials, broker access, or cross-account behavior.
