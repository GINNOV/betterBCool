import { climateState } from "@/lib/bosch";
import { authenticateTV } from "@/lib/tv-pairing";

export async function GET(request: Request) {
  const identity = await authenticateTV(request, "climate:read");
  if (!identity) return Response.json({ error: "Unauthorized" }, { status: 401 });
  try { return Response.json(await climateState(identity.installationID)); }
  catch (error) {
    const message = error instanceof Error ? error.message : "Climate state failed";
    return Response.json({ error: message }, { status: 502 });
  }
}
