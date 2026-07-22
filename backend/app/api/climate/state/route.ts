import { authenticate, unauthorized } from "@/lib/auth";
import { climateState } from "@/lib/bosch";

export async function GET(request: Request) {
  const identity = authenticate(request);
  if (!identity) return unauthorized();
  try { return Response.json(await climateState(identity.installationID)); }
  catch (error) {
    const message = error instanceof Error ? error.message : "Climate state failed";
    return Response.json({ error: message }, { status: 502 });
  }
}
