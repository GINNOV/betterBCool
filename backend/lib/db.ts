import { neon } from "@neondatabase/serverless";
import type { ClimateSchedule, Transport } from "./types";

let schemaReady: Promise<void> | undefined;

export function getSql() {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is not configured");
  return neon(url);
}

export async function ensureSchema(): Promise<void> {
  schemaReady ??= createSchema().catch((error) => {
    schemaReady = undefined;
    throw error;
  });
  return schemaReady;
}

async function createSchema(): Promise<void> {
  const sql = getSql();
  await sql`
    CREATE TABLE IF NOT EXISTS installations (
      id TEXT PRIMARY KEY,
      token_ciphertext TEXT NOT NULL,
      token_version BIGINT NOT NULL DEFAULT 1,
      refresh_lease_until TIMESTAMPTZ,
      gateway_id TEXT NOT NULL,
      transport TEXT NOT NULL CHECK (transport IN ('pointT', 'bacon')),
      region TEXT NOT NULL DEFAULT 'euc1',
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `;
  await sql`
    CREATE TABLE IF NOT EXISTS schedules (
      installation_id TEXT NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
      id TEXT NOT NULL,
      revision BIGINT NOT NULL,
      body JSONB NOT NULL,
      timezone TEXT NOT NULL,
      workflow_run_id TEXT,
      last_execution_at TIMESTAMPTZ,
      last_status TEXT,
      last_error TEXT,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (installation_id, id)
    )
  `;
  await sql`
    CREATE TABLE IF NOT EXISTS executions (
      installation_id TEXT NOT NULL,
      schedule_id TEXT NOT NULL,
      occurrence_id TEXT NOT NULL,
      step_id TEXT NOT NULL,
      executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (installation_id, schedule_id, occurrence_id, step_id)
    )
  `;
  await sql`
    CREATE TABLE IF NOT EXISTS tv_pairing_sessions (
      id TEXT PRIMARY KEY,
      code_hash TEXT NOT NULL UNIQUE,
      polling_secret_hash TEXT NOT NULL,
      installation_id TEXT REFERENCES installations(id) ON DELETE CASCADE,
      tv_name TEXT,
      expires_at TIMESTAMPTZ NOT NULL,
      approved_at TIMESTAMPTZ,
      exchanged_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `;
  await sql`
    CREATE INDEX IF NOT EXISTS tv_pairing_sessions_expiry_idx
    ON tv_pairing_sessions (expires_at)
  `;
  await sql`
    CREATE TABLE IF NOT EXISTS tv_devices (
      id TEXT PRIMARY KEY,
      installation_id TEXT NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      token_hash TEXT NOT NULL UNIQUE,
      scopes TEXT[] NOT NULL DEFAULT ARRAY['climate:read', 'climate:write'],
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_used_at TIMESTAMPTZ,
      revoked_at TIMESTAMPTZ
    )
  `;
  await sql`
    CREATE INDEX IF NOT EXISTS tv_devices_installation_idx
    ON tv_devices (installation_id)
  `;
}

export interface InstallationRow {
  id: string;
  token_ciphertext: string;
  token_version: string;
  gateway_id: string;
  transport: Transport;
  region: "euc1" | "use1";
}

export interface ScheduleRow {
  installation_id: string;
  id: string;
  revision: string;
  body: ClimateSchedule;
  timezone: string;
  workflow_run_id: string | null;
  last_execution_at: string | null;
  last_status: string | null;
  last_error: string | null;
}

export async function installation(id: string): Promise<InstallationRow | undefined> {
  await ensureSchema();
  const rows = await getSql()`SELECT * FROM installations WHERE id = ${id}`;
  return rows[0] as unknown as InstallationRow | undefined;
}

export async function schedule(installationID: string, scheduleID: string): Promise<ScheduleRow | undefined> {
  await ensureSchema();
  const rows = await getSql()`
    SELECT * FROM schedules WHERE installation_id = ${installationID} AND id = ${scheduleID}
  `;
  return rows[0] as unknown as ScheduleRow | undefined;
}
