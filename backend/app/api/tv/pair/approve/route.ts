import { authenticate, unauthorized } from "@/lib/auth";
import { approveTVPairing } from "@/lib/tv-pairing";

export async function POST(request: Request) {
  const identity = authenticate(request);
  if (!identity) return unauthorized();
  const body = await request.json().catch(() => null) as { code?: unknown; tvName?: unknown } | null;
  if (typeof body?.code !== "string") {
    return Response.json({ error: "A six-digit pairing code is required" }, { status: 400 });
  }
  const approval = await approveTVPairing(body.code, identity.installationID, body.tvName);
  if (!approval) return Response.json({ error: "Pairing code is invalid or expired" }, { status: 409 });
  return Response.json({ ok: true, ...approval });
}
