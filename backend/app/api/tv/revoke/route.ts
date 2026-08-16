import { authenticate, unauthorized } from "@/lib/auth";
import { revokeTVDevice } from "@/lib/tv-pairing";

export async function POST(request: Request) {
  const identity = authenticate(request);
  if (!identity) return unauthorized();
  const body = await request.json().catch(() => null) as { deviceID?: unknown } | null;
  if (typeof body?.deviceID !== "string" || !body.deviceID) {
    return Response.json({ error: "A TV device ID is required" }, { status: 400 });
  }
  const revoked = await revokeTVDevice(identity.installationID, body.deviceID);
  return Response.json({ ok: true, revoked });
}
