import { authenticate, unauthorized } from "@/lib/auth";
import { ensureSchema, getSql, schedule as loadSchedule } from "@/lib/db";
import { scheduleRequestSchema } from "@/lib/schemas";
import { climateRoutineWorkflow } from "@/workflows/climate-routine";
import { getRun, start } from "workflow/api";

interface Context { params: Promise<{ id: string }> }

export async function PUT(request: Request, context: Context) {
  const identity = authenticate(request);
  if (!identity) return unauthorized();
  const { id } = await context.params;
  const parsed = scheduleRequestSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success || parsed.data.schedule.id !== id) {
    return Response.json({ error: "Invalid schedule payload" }, { status: 400 });
  }
  try { new Intl.DateTimeFormat("en", { timeZone: parsed.data.timezone }); }
  catch { return Response.json({ error: "Invalid timezone" }, { status: 400 }); }

  await ensureSchema();
  const previous = await loadSchedule(identity.installationID, id);
  const scheduleUnchanged = previous
    && previous.timezone === parsed.data.timezone
    && canonicalJSON(previous.body) === canonicalJSON(parsed.data.schedule);
  if (scheduleUnchanged && (!parsed.data.schedule.isEnabled || previous.workflow_run_id)) {
    return Response.json({
      ok: true,
      revision: Number(previous.revision),
      status: parsed.data.schedule.isEnabled ? "scheduled" : "disabled",
      runID: previous.workflow_run_id ?? undefined,
    });
  }

  const revision = Number(previous?.revision ?? 0) + 1;
  if (previous?.workflow_run_id) await getRun(previous.workflow_run_id).cancel().catch(() => undefined);

  const sql = getSql();
  await sql`
    INSERT INTO schedules (installation_id, id, revision, body, timezone, last_status, updated_at)
    VALUES (${identity.installationID}, ${id}, ${revision}, ${JSON.stringify(parsed.data.schedule)}, ${parsed.data.timezone}, 'starting', NOW())
    ON CONFLICT (installation_id, id) DO UPDATE SET
      revision = EXCLUDED.revision,
      body = EXCLUDED.body,
      timezone = EXCLUDED.timezone,
      workflow_run_id = NULL,
      last_status = EXCLUDED.last_status,
      last_error = NULL,
      updated_at = NOW()
  `;

  if (!parsed.data.schedule.isEnabled) {
    await sql`UPDATE schedules SET last_status = 'disabled' WHERE installation_id = ${identity.installationID} AND id = ${id}`;
    return Response.json({ ok: true, revision, status: "disabled" });
  }

  try {
    const run = await start(climateRoutineWorkflow, [identity.installationID, id, revision]);
    await sql`
      UPDATE schedules SET workflow_run_id = ${run.runId}, last_status = 'scheduled'
      WHERE installation_id = ${identity.installationID} AND id = ${id} AND revision = ${revision}
    `;
    return Response.json({ ok: true, revision, status: "scheduled", runID: run.runId });
  } catch (error) {
    const message = error instanceof Error ? error.message.slice(0, 500) : "Workflow start failed";
    await sql`
      UPDATE schedules SET last_status = 'failed', last_error = ${message}
      WHERE installation_id = ${identity.installationID} AND id = ${id} AND revision = ${revision}
    `;
    return Response.json({ error: "Unable to start schedule workflow" }, { status: 503 });
  }
}

function canonicalJSON(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const object = value as Record<string, unknown>;
    return `{${Object.keys(object).sort().map((key) => `${JSON.stringify(key)}:${canonicalJSON(object[key])}`).join(",")}}`;
  }
  return JSON.stringify(value) ?? "undefined";
}

export async function DELETE(request: Request, context: Context) {
  const identity = authenticate(request);
  if (!identity) return unauthorized();
  const { id } = await context.params;
  const previous = await loadSchedule(identity.installationID, id);
  if (previous?.workflow_run_id) await getRun(previous.workflow_run_id).cancel().catch(() => undefined);
  await ensureSchema();
  await getSql()`DELETE FROM schedules WHERE installation_id = ${identity.installationID} AND id = ${id}`;
  return Response.json({ ok: true });
}
