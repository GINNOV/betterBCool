import { createHash, randomBytes, randomUUID, timingSafeEqual, randomInt } from "node:crypto";
import { ensureSchema, getSql } from "./db";

const PAIRING_TTL_MS = 5 * 60 * 1000;
const TOKEN_BYTES = 32;

export type TVScope = "climate:read" | "climate:write";

export interface TVPairingStart {
  sessionID: string;
  code: string;
  pollingSecret: string;
  expiresAt: string;
}

export interface TVDeviceIdentity {
  deviceID: string;
  installationID: string;
  name: string;
  scopes: TVScope[];
}

export interface TVPairingApproval {
  sessionID: string;
  installationID: string;
  tvName: string;
}

export type TVPairingStatus = "pending" | "approved" | "exchanged" | "expired" | "invalid";

export interface TVPairingExchange {
  status: "pending" | "approved" | "exchanged";
  token?: string;
  device?: TVDeviceIdentity;
  expiresAt?: string;
}

export function hashSecret(secret: string): string {
  return createHash("sha256").update(secret, "utf8").digest("hex");
}

export function normalizePairingCode(code: string): string {
  return code.replace(/[^0-9]/g, "").slice(0, 6);
}

export function generatePairingCode(): string {
  return randomInt(100_000, 1_000_000).toString();
}

export function generatePollingSecret(): string {
  return randomBytes(TOKEN_BYTES).toString("base64url");
}

export function safeSecretEqual(left: string, right: string): boolean {
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}

export function normalizeTVName(name: unknown): string {
  if (typeof name !== "string") return "Living Room TV";
  const value = name.trim().replace(/\s+/g, " ").slice(0, 64);
  return value || "Living Room TV";
}

export async function startTVPairing(): Promise<TVPairingStart> {
  await ensureSchema();
  const sessionID = randomUUID();
  const code = generatePairingCode();
  const pollingSecret = generatePollingSecret();
  const expiresAt = new Date(Date.now() + PAIRING_TTL_MS);
  await getSql()`
    INSERT INTO tv_pairing_sessions (id, code_hash, polling_secret_hash, expires_at)
    VALUES (${sessionID}, ${hashSecret(code)}, ${hashSecret(pollingSecret)}, ${expiresAt.toISOString()})
  `;
  return { sessionID, code, pollingSecret, expiresAt: expiresAt.toISOString() };
}

export async function approveTVPairing(
  code: string,
  installationID: string,
  tvName?: unknown,
): Promise<TVPairingApproval | undefined> {
  const normalizedCode = normalizePairingCode(code);
  if (normalizedCode.length !== 6) return undefined;
  await ensureSchema();
  const name = normalizeTVName(tvName);
  const rows = await getSql()`
    UPDATE tv_pairing_sessions
    SET installation_id = ${installationID}, tv_name = ${name}, approved_at = NOW()
    WHERE code_hash = ${hashSecret(normalizedCode)}
      AND expires_at > NOW()
      AND approved_at IS NULL
      AND exchanged_at IS NULL
    RETURNING id
  `;
  const row = rows[0] as { id: string } | undefined;
  return row ? { sessionID: row.id, installationID, tvName: name } : undefined;
}

export async function tvPairingStatus(
  sessionID: string,
  pollingSecret: string,
): Promise<TVPairingStatus> {
  if (!sessionID || !pollingSecret) return "invalid";
  await ensureSchema();
  const rows = await getSql()`
    SELECT polling_secret_hash, expires_at, approved_at, exchanged_at
    FROM tv_pairing_sessions
    WHERE id = ${sessionID}
  `;
  const row = rows[0] as {
    polling_secret_hash: string;
    expires_at: string | Date;
    approved_at: string | Date | null;
    exchanged_at: string | Date | null;
  } | undefined;
  if (!row || !safeSecretEqual(row.polling_secret_hash, hashSecret(pollingSecret))) return "invalid";
  if (new Date(row.expires_at).getTime() <= Date.now() && !row.exchanged_at) return "expired";
  if (row.exchanged_at) return "exchanged";
  return row.approved_at ? "approved" : "pending";
}

export async function exchangeTVPairing(
  sessionID: string,
  pollingSecret: string,
): Promise<TVPairingExchange | undefined> {
  if (!sessionID || !pollingSecret) return undefined;
  await ensureSchema();
  const rows = await getSql()`
    SELECT installation_id, tv_name, expires_at, approved_at, exchanged_at, polling_secret_hash
    FROM tv_pairing_sessions
    WHERE id = ${sessionID}
  `;
  const session = rows[0] as {
    installation_id: string | null;
    tv_name: string | null;
    expires_at: string | Date;
    approved_at: string | Date | null;
    exchanged_at: string | Date | null;
    polling_secret_hash: string;
  } | undefined;
  if (!session || !safeSecretEqual(session.polling_secret_hash, hashSecret(pollingSecret))) return undefined;
  if (session.exchanged_at) return { status: "exchanged" };
  if (new Date(session.expires_at).getTime() <= Date.now()) return undefined;
  if (!session.approved_at || !session.installation_id) return { status: "pending" };

  const token = generatePollingSecret();
  const deviceID = randomUUID();
  const name = normalizeTVName(session.tv_name);
  await getSql()`
    INSERT INTO tv_devices (id, installation_id, name, token_hash)
    VALUES (${deviceID}, ${session.installation_id}, ${name}, ${hashSecret(token)})
  `;
  const claimed = await getSql()`
    UPDATE tv_pairing_sessions
    SET exchanged_at = NOW()
    WHERE id = ${sessionID}
      AND exchanged_at IS NULL
      AND approved_at IS NOT NULL
      AND expires_at > NOW()
    RETURNING id
  `;
  if (!claimed[0]) {
    await getSql()`DELETE FROM tv_devices WHERE id = ${deviceID}`;
    return { status: "exchanged" };
  }
  return {
    status: "approved",
    token,
    device: {
      deviceID,
      installationID: session.installation_id,
      name,
      scopes: ["climate:read", "climate:write"],
    },
    expiresAt: session.expires_at instanceof Date
      ? session.expires_at.toISOString()
      : new Date(session.expires_at).toISOString(),
  };
}

export async function authenticateTV(
  request: Request,
  requiredScope?: TVScope,
): Promise<TVDeviceIdentity | null> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("TVBearer ")) return null;
  const token = authorization.slice("TVBearer ".length).trim();
  if (token.length < 32 || token.length > 256) return null;
  await ensureSchema();
  const rows = await getSql()`
    SELECT id, installation_id, name, scopes
    FROM tv_devices
    WHERE token_hash = ${hashSecret(token)}
      AND revoked_at IS NULL
  `;
  const row = rows[0] as {
    id: string;
    installation_id: string;
    name: string;
    scopes: string[];
  } | undefined;
  if (!row) return null;
  const scopes = row.scopes.filter((scope): scope is TVScope => scope === "climate:read" || scope === "climate:write");
  if (requiredScope && !scopes.includes(requiredScope)) return null;
  await getSql()`UPDATE tv_devices SET last_used_at = NOW() WHERE id = ${row.id}`;
  return { deviceID: row.id, installationID: row.installation_id, name: row.name, scopes };
}

export async function revokeTVDevice(installationID: string, deviceID: string): Promise<boolean> {
  await ensureSchema();
  const rows = await getSql()`
    UPDATE tv_devices
    SET revoked_at = NOW()
    WHERE id = ${deviceID} AND installation_id = ${installationID} AND revoked_at IS NULL
    RETURNING id
  `;
  return Boolean(rows[0]);
}
