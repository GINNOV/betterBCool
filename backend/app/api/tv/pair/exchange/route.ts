import { exchangeTVPairing } from "@/lib/tv-pairing";

export async function POST(request: Request) {
  const body = await request.json().catch(() => null) as { sessionID?: unknown; pollingSecret?: unknown } | null;
  if (typeof body?.sessionID !== "string" || typeof body.pollingSecret !== "string") {
    return Response.json({ error: "Pairing session details are required" }, { status: 400 });
  }
  const exchange = await exchangeTVPairing(body.sessionID, body.pollingSecret);
  if (!exchange) return Response.json({ error: "Pairing session is invalid or expired" }, { status: 404 });
  if (exchange.status === "pending") return Response.json(exchange, { status: 202 });
  if (exchange.status === "exchanged") return Response.json({ error: "Pairing session has already been exchanged" }, { status: 409 });
  return Response.json(exchange, { headers: { "Cache-Control": "no-store" } });
}
