import { createHash, randomUUID } from "node:crypto";
import WebSocket from "ws";
import { decryptTokens, encryptTokens } from "./token-crypto";
import { ensureSchema, getSql, installation, type InstallationRow } from "./db";
import type { ClimatePatch, ClimateState, OAuthTokens } from "./types";

const CLIENT_ID = "762162C0-FA2D-4540-AE66-6489F189FADC";
const TOKEN_URL = "https://singlekey-id.com/auth/connect/token";
const POINT_T_URL = "https://pointt-api.bosch-thermotechnology.com";
const USER_AGENT = "DashApp/4.0.0 (iOS)";

export async function accessToken(installationID: string): Promise<string> {
  const row = await installation(installationID);
  if (!row) throw new Error("Installation credentials are missing");
  const tokens = decryptTokens(row.token_ciphertext);
  if (new Date(tokens.expiresAt).getTime() > Date.now() + 60_000) return tokens.accessToken;

  const sql = getSql();
  const lease = await sql`
    UPDATE installations
    SET refresh_lease_until = NOW() + INTERVAL '30 seconds'
    WHERE id = ${installationID}
      AND (refresh_lease_until IS NULL OR refresh_lease_until < NOW())
    RETURNING id
  `;

  if (lease.length === 0) {
    for (let attempt = 0; attempt < 20; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 1_000));
      const latest = await installation(installationID);
      if (!latest) throw new Error("Installation was removed");
      if (latest.token_version !== row.token_version) {
        return decryptTokens(latest.token_ciphertext).accessToken;
      }
    }
    throw new Error("Timed out waiting for token refresh");
  }

  try {
    const refreshed = await refreshTokens(tokens.refreshToken);
    await sql`
      UPDATE installations
      SET token_ciphertext = ${encryptTokens(refreshed)},
          token_version = token_version + 1,
          refresh_lease_until = NULL,
          updated_at = NOW()
      WHERE id = ${installationID}
    `;
    return refreshed.accessToken;
  } catch (error) {
    await sql`UPDATE installations SET refresh_lease_until = NULL WHERE id = ${installationID}`;
    throw error;
  }
}

async function refreshTokens(refreshToken: string): Promise<OAuthTokens> {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    client_id: CLIENT_ID,
    refresh_token: refreshToken,
  });
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!response.ok) throw new Error(`Bosch token refresh failed (${response.status})`);
  const value = (await response.json()) as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
  };
  if (!value.access_token || !value.expires_in) throw new Error("Bosch returned an invalid token response");
  return {
    accessToken: value.access_token,
    refreshToken: value.refresh_token ?? refreshToken,
    expiresAt: new Date(Date.now() + value.expires_in * 1_000).toISOString(),
  };
}

export async function climateState(installationID: string): Promise<ClimateState> {
  const row = await requiredInstallation(installationID);
  const token = await accessToken(installationID);
  if (row.transport === "bacon") {
    return stateFromBacon(await baconShadow(row, token));
  }
  return pointTState(row, token);
}

export async function applyClimatePatch(installationID: string, patch: ClimatePatch): Promise<ClimateState> {
  const row = await requiredInstallation(installationID);
  validatePatch(patch, row);
  const token = await accessToken(installationID);

  if (row.transport === "bacon") {
    const desired: Record<string, unknown> = {};
    if (patch.powerEnabled !== undefined) desired.powerEnabled = patch.powerEnabled;
    if (patch.operatingMode !== undefined) desired.opMode = patch.operatingMode;
    if (patch.fanSpeed !== undefined) desired.fanSpeed = patch.fanSpeed;
    if (patch.temperatureSetpoint !== undefined) desired.tempSetpoint = patch.temperatureSetpoint;
    if (patch.horizontalSwingEnabled !== undefined) desired.hSwingEnabled = patch.horizontalSwingEnabled;
    if (patch.verticalSwingEnabled !== undefined) desired.vSwingEnabled = patch.verticalSwingEnabled;
    return stateFromBacon(await baconShadow(row, token, desired));
  }

  const writes: Array<[string, unknown]> = [];
  if (patch.powerEnabled !== undefined) writes.push(["acControl", patch.powerEnabled ? "on" : "off"]);
  if (patch.operatingMode !== undefined) writes.push(["operationMode", patch.operatingMode === "fan" ? "fanOnly" : patch.operatingMode]);
  if (patch.fanSpeed !== undefined) writes.push(["fanSpeed", patch.fanSpeed]);
  if (patch.temperatureSetpoint !== undefined) writes.push(["temperatureSetpoint", patch.temperatureSetpoint]);
  if (patch.verticalSwingEnabled !== undefined) writes.push(["airFlowVertical", patch.verticalSwingEnabled ? "on" : "off"]);
  if (patch.horizontalSwingEnabled !== undefined) writes.push(["airFlowHorizontal", patch.horizontalSwingEnabled ? "on" : "off"]);
  for (const [resource, value] of writes) await pointTWrite(row, token, resource, value);
  return pointTState(row, token);
}

async function requiredInstallation(id: string): Promise<InstallationRow> {
  await ensureSchema();
  const row = await installation(id);
  if (!row) throw new Error("Installation credentials are missing");
  return row;
}

export function validatePatch(patch: ClimatePatch, row: InstallationRow): void {
  const min = row.transport === "bacon" ? 16 : 15;
  const max = row.transport === "bacon" ? 30 : 32.5;
  const step = 0.5;
  if (patch.temperatureSetpoint !== undefined) {
    const value = patch.temperatureSetpoint;
    if (!Number.isFinite(value) || value < min || value > max || Math.abs((value - min) / step - Math.round((value - min) / step)) > 1e-7) {
      throw new Error("Unsupported temperature setpoint");
    }
  }
  if (row.transport === "pointT" && patch.fanSpeed && ["high", "turbo"].includes(patch.fanSpeed)) {
    throw new Error("Unsupported PointT fan speed");
  }
}

async function pointTRequest(row: InstallationRow, token: string, resource: string): Promise<unknown> {
  const url = `${POINT_T_URL}/pointt-api/api/v1/gateways/${encodeURIComponent(row.gateway_id)}/resource/airConditioning/${resource}`;
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}`, Accept: "application/json" } });
  if (!response.ok) throw new Error(`Bosch PointT read failed (${response.status})`);
  const body = (await response.json()) as { value?: unknown } | unknown;
  return typeof body === "object" && body !== null && "value" in body ? (body as { value: unknown }).value : body;
}

async function pointTWrite(row: InstallationRow, token: string, resource: string, value: unknown): Promise<void> {
  const url = `${POINT_T_URL}/pointt-api/api/v1/gateways/${encodeURIComponent(row.gateway_id)}/resource/airConditioning/${resource}`;
  const response = await fetch(url, {
    method: "PUT",
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json", "Content-Type": "application/json" },
    body: JSON.stringify({ value }),
  });
  if (!response.ok) throw new Error(`Bosch PointT write failed (${response.status})`);
}

async function pointTState(row: InstallationRow, token: string): Promise<ClimateState> {
  const [power, mode, fan, room, setpoint, eco, sleepMode, vertical, horizontal] = await Promise.all([
    pointTRequest(row, token, "acControl"), pointTRequest(row, token, "operationMode"),
    pointTRequest(row, token, "fanSpeed"), pointTRequest(row, token, "roomTemperature"),
    pointTRequest(row, token, "temperatureSetpoint"), optionalPointT(row, token, "ecoMode"),
    optionalPointT(row, token, "sleepMode"), optionalPointT(row, token, "airFlowVertical"),
    optionalPointT(row, token, "airFlowHorizontal"),
  ]);
  return {
    timestamp: new Date().toISOString(), powerEnabled: enabled(power),
    operatingMode: mode === "fanOnly" ? "fan" : (mode as ClimateState["operatingMode"]),
    fanSpeed: typeof fan === "string" ? fan as ClimateState["fanSpeed"] : null,
    roomTemperature: typeof room === "number" ? room : null,
    temperatureSetpoint: typeof setpoint === "number" ? setpoint : null,
    breezeAwayEnabled: false, ecoEnabled: enabled(eco), fullPowerEnabled: false,
    horizontalSwingEnabled: enabled(horizontal), ionizerEnabled: false, setbackEnabled: false,
    sleepEnabled: enabled(sleepMode), verticalSwingEnabled: enabled(vertical),
  };
}

async function optionalPointT(row: InstallationRow, token: string, resource: string): Promise<unknown> {
  try { return await pointTRequest(row, token, resource); } catch { return null; }
}

function enabled(value: unknown): boolean {
  return value === true || (typeof value === "string" && ["on", "enabled", "true"].includes(value.toLowerCase()));
}

function stateFromBacon(values: Record<string, unknown>): ClimateState {
  if (typeof values.powerEnabled !== "boolean" || typeof values.opMode !== "string") {
    throw new Error("Bosch returned an invalid device shadow");
  }
  return {
    timestamp: new Date().toISOString(), powerEnabled: values.powerEnabled,
    operatingMode: values.opMode as ClimateState["operatingMode"],
    fanSpeed: typeof values.fanSpeed === "string" ? values.fanSpeed as ClimateState["fanSpeed"] : null,
    roomTemperature: typeof values.roomTemperature === "number" ? values.roomTemperature : null,
    temperatureSetpoint: typeof values.tempSetpoint === "number" ? values.tempSetpoint : null,
    breezeAwayEnabled: values.breezeAwayEnabled === true, ecoEnabled: values.ecoEnabled === true,
    fullPowerEnabled: values.fullPowerEnabled === true, horizontalSwingEnabled: values.hSwingEnabled === true,
    ionizerEnabled: values.ionizerEnabled === true, setbackEnabled: values.setbackEnabled === true,
    sleepEnabled: values.sleepEnabled === true, verticalSwingEnabled: values.vSwingEnabled === true,
  };
}

async function baconShadow(row: InstallationRow, token: string, desired?: Record<string, unknown>): Promise<Record<string, unknown>> {
  const subject = jwtSubject(token);
  const host = `broker.${row.region}.bacon.bosch-tt-cw.com`;
  const socket = new MQTTWebSocket(`wss://${host}:443/mqtt`, subject, token);
  try {
    await socket.connect();
    await socket.subscribe(`users/${subject}/#`);
    const root = `users/${subject}/devices/${row.gateway_id}/shadows/state`;
    if (desired) {
      await socket.publish(`${root}/update`, Buffer.from(JSON.stringify({ state: { desired } })));
      await socket.waitForTopic(`${root}/update/accepted`, `${root}/update/rejected`);
    }
    await socket.publish(`${root}/get`, Buffer.alloc(0));
    const payload = await socket.waitForTopic(`${root}/get/accepted`, `${root}/get/rejected`);
    const decoded = JSON.parse(payload.toString("utf8")) as { state?: { reported?: Record<string, unknown> } };
    if (!decoded.state?.reported) throw new Error("Bosch returned an invalid device shadow");
    return decoded.state.reported;
  } finally {
    socket.close();
  }
}

function jwtSubject(token: string): string {
  const part = token.split(".")[1];
  if (!part) throw new Error("Bosch access token is invalid");
  const payload = JSON.parse(Buffer.from(part, "base64url").toString("utf8")) as { sub?: string };
  if (!payload.sub) throw new Error("Bosch access token has no subject");
  return payload.sub;
}

class MQTTWebSocket {
  private socket?: WebSocket;
  private queue: Buffer[] = [];
  private waiters: Array<(value: Buffer) => void> = [];
  private packetID = 1;

  constructor(private readonly url: string, private readonly subject: string, private readonly token: string) {}

  async connect(): Promise<void> {
    this.socket = new WebSocket(this.url, "mqtt", {
      headers: { Authorization: `Bearer ${this.token}`, "User-Agent": USER_AGENT },
      handshakeTimeout: 20_000,
    });
    this.socket.on("message", (data) => this.push(Buffer.isBuffer(data) ? data : Buffer.from(data as ArrayBuffer)));
    await new Promise<void>((resolve, reject) => {
      this.socket!.once("open", resolve);
      this.socket!.once("error", reject);
    });
    this.send(mqttConnect(createHash("sha256").update(randomUUID()).digest("hex"), this.subject, this.token));
    const packet = mqttDecode(await this.receive());
    if (packet.type !== 2 || packet.body[1] !== 0) throw new Error("Bosch MQTT connection was refused");
  }

  async subscribe(topic: string): Promise<void> {
    this.send(mqttSubscribe(topic, this.packetID++));
    while (mqttDecode(await this.receive()).type !== 9) {}
  }

  async publish(topic: string, payload: Buffer): Promise<void> { this.send(mqttPublish(topic, payload)); }

  async waitForTopic(accepted: string, rejected: string): Promise<Buffer> {
    const timeout = new Promise<never>((_, reject) => setTimeout(() => reject(new Error("Bosch MQTT timed out")), 15_000));
    const messages = (async () => {
      while (true) {
        const publish = mqttDecodePublish(mqttDecode(await this.receive()));
        if (!publish) continue;
        if (publish.topic === rejected) throw new Error("Bosch rejected the device shadow request");
        if (publish.topic === accepted) return publish.payload;
      }
    })();
    return Promise.race([messages, timeout]);
  }

  close(): void { this.socket?.close(); }
  private send(data: Buffer): void { this.socket?.send(data); }
  private push(data: Buffer): void { const waiter = this.waiters.shift(); waiter ? waiter(data) : this.queue.push(data); }
  private receive(): Promise<Buffer> {
    const value = this.queue.shift();
    return value ? Promise.resolve(value) : new Promise((resolve) => this.waiters.push(resolve));
  }
}

function mqttConnect(clientID: string, username: string, password: string): Buffer {
  return mqttPacket(0x10, Buffer.concat([mqttString("MQTT"), Buffer.from([5, 0xc2, 0, 60, 0]), mqttString(clientID), mqttString(username), mqttString(password)]));
}
function mqttSubscribe(topic: string, id: number): Buffer {
  return mqttPacket(0x82, Buffer.concat([Buffer.from([id >> 8, id & 0xff, 0]), mqttString(topic), Buffer.from([0])]));
}
function mqttPublish(topic: string, payload: Buffer): Buffer { return mqttPacket(0x30, Buffer.concat([mqttString(topic), Buffer.from([0]), payload])); }
function mqttString(value: string): Buffer { const data = Buffer.from(value); return Buffer.concat([Buffer.from([data.length >> 8, data.length & 0xff]), data]); }
function mqttPacket(header: number, body: Buffer): Buffer { return Buffer.concat([Buffer.from([header]), mqttVariable(body.length), body]); }
function mqttVariable(input: number): Buffer { const bytes: number[] = []; let value = input; do { let byte = value % 128; value = Math.floor(value / 128); if (value) byte |= 0x80; bytes.push(byte); } while (value); return Buffer.from(bytes); }
function mqttDecode(data: Buffer): { type: number; flags: number; body: Buffer } {
  if (!data.length) throw new Error("Malformed MQTT packet");
  const [length, index] = mqttDecodeVariable(data, 1);
  if (index + length > data.length) throw new Error("Malformed MQTT packet");
  return { type: data[0] >> 4, flags: data[0] & 15, body: data.subarray(index, index + length) };
}
function mqttDecodeVariable(data: Buffer, start: number): [number, number] { let value = 0, multiplier = 1, index = start; while (index < data.length && multiplier <= 128 ** 3) { const byte = data[index++]; value += (byte & 127) * multiplier; if (!(byte & 128)) return [value, index]; multiplier *= 128; } throw new Error("Malformed MQTT packet"); }
function mqttDecodePublish(packet: { type: number; flags: number; body: Buffer }): { topic: string; payload: Buffer } | undefined {
  if (packet.type !== 3 || packet.body.length < 2) return undefined;
  const topicLength = packet.body.readUInt16BE(0); let index = 2 + topicLength;
  const topic = packet.body.subarray(2, index).toString("utf8");
  if (((packet.flags >> 1) & 3) > 0) index += 2;
  const [propertiesLength, propertiesEnd] = mqttDecodeVariable(packet.body, index);
  index = propertiesEnd + propertiesLength;
  return { topic, payload: packet.body.subarray(index) };
}
