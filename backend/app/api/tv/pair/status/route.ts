import { tvPairingStatus } from "@/lib/tv-pairing";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const sessionID = url.searchParams.get("sessionID") ?? "";
  const pollingSecret = url.searchParams.get("pollingSecret") ?? "";
  const status = await tvPairingStatus(sessionID, pollingSecret);
  if (status === "invalid") return Response.json({ error: "Pairing session not found" }, { status: 404 });
  return Response.json({ status }, { headers: { "Cache-Control": "no-store" } });
}
