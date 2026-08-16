import { applyClimatePatch } from "@/lib/bosch";
import { authenticateTV } from "@/lib/tv-pairing";
import { patchSchema } from "@/lib/schemas";

export async function PUT(request: Request) {
  const identity = await authenticateTV(request, "climate:write");
  if (!identity) return Response.json({ error: "Unauthorized" }, { status: 401 });
  const parsed = patchSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success || Object.keys(parsed.data).length === 0) {
    return Response.json({ error: "Invalid climate patch" }, { status: 400 });
  }
  try { return Response.json(await applyClimatePatch(identity.installationID, parsed.data)); }
  catch (error) {
    const message = error instanceof Error ? error.message : "Climate command failed";
    return Response.json({ error: message }, { status: 502 });
  }
}
