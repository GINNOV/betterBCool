# betterBCool Cloud

This is the private Vercel companion service for reliable climate scheduling. It uses:

- Vercel Workflow for durable waits and automatic step retries
- Neon Postgres for schedules, execution status, and encrypted Bosch credentials
- AES-256-GCM application-level encryption for OAuth tokens
- A shared API key plus a per-installation identifier for app requests

## Production

The current production deployment is:

`https://betterbcool-cloud.vercel.app`

The project is linked to `ginnovs-projects/betterbcool-cloud` and its Neon resource is connected through Vercel Marketplace.

## Required environment variables

- `DATABASE_URL` — injected by the Neon integration
- `APP_API_KEY` — a random 32-byte API secret
- `TOKEN_ENCRYPTION_KEY` — a base64-encoded 32-byte AES key

Never commit their values. The production API key generated during setup is also stored in the local macOS Keychain under service `dev.betterbcool.vercel` and account `cloud-api-key`.

## Local verification

```sh
npm install
npm test
npm run typecheck
npm run build
```

The database schema is created idempotently on the first authenticated request.

## Security model

When cloud scheduling is enabled, Vercel becomes the single authority for Bosch token refreshes. The iOS app routes manual and scheduled commands through the backend, preventing the phone and server from racing to rotate the same refresh token. Routine updates increment a revision and cancel the previous workflow; every delayed step checks that revision again before changing the device.
