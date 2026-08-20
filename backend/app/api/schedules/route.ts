import { authenticate, unauthorized } from "@/lib/auth";
import { ensureSchema, getSql } from "@/lib/db";
import { getRun } from "workflow/api";

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

export async function DELETE(request: Request) {
  const identity = authenticate(request);
  if (!identity) return unauthorized();
  await ensureSchema();
  const sql = getSql();
  const rows = await sql`
    SELECT id, workflow_run_id
    FROM schedules
    WHERE installation_id = ${identity.installationID}
  `;
  for (const row of rows) {
    if (row.workflow_run_id) await getRun(String(row.workflow_run_id)).cancel().catch(() => undefined);
  }
  await sql`DELETE FROM schedules WHERE installation_id = ${identity.installationID}`;
  return Response.json({ ok: true });
}
