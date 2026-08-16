import { authenticateTV } from "@/lib/tv-pairing";

export async function GET(request: Request) {
  const identity = await authenticateTV(request);
  if (!identity) return Response.json({ error: "Unauthorized" }, { status: 401 });
  return Response.json(identity, { headers: { "Cache-Control": "no-store" } });
}
