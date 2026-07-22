import { authenticate, unauthorized } from "@/lib/auth";
import { applyClimatePatch } from "@/lib/bosch";
import { patchSchema } from "@/lib/schemas";

export async function PUT(request: Request) {
  const identity = authenticate(request);
  if (!identity) return unauthorized();
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
