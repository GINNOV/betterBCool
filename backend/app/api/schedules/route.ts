import { authenticate, unauthorized } from "@/lib/auth";
import { ensureSchema, getSql } from "@/lib/db";

export async function GET(request: Request) {
  const identity = authenticate(request);
  if (!identity) return unauthorized();
  await ensureSchema();
  const rows = await getSql()`
    SELECT id, revision, workflow_run_id, last_execution_at, last_status, last_error
    FROM schedules
    WHERE installation_id = ${identity.installationID}
    ORDER BY updated_at DESC
  `;
  return Response.json({ schedules: rows });
}
