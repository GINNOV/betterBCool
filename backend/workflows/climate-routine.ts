import { FatalError, sleep } from "workflow";
import { applyClimatePatch } from "@/lib/bosch";
import { getSql, schedule as loadSchedule } from "@/lib/db";
import { plannedTransition } from "@/lib/schedule-time";
import type { PlannedTransition } from "@/lib/types";

export async function climateRoutineWorkflow(
  installationID: string,
  scheduleID: string,
  revision: number,
) {
  "use workflow";

  let cursor = new Date();
  let includeCurrent = true;
  while (true) {
    const transition = await findTransition(installationID, scheduleID, revision, cursor, includeCurrent);
    if (!transition) return { status: "superseded" };

    const executeAt = new Date(transition.executeAt);
    if (executeAt.getTime() > Date.now()) await sleep(executeAt);
    const result = await executeTransition(installationID, transition);
    if (result === "superseded") return { status: result };

    cursor = new Date(executeAt.getTime() + 1);
    includeCurrent = false;
  }
}

async function findTransition(
  installationID: string,
  scheduleID: string,
  revision: number,
  after: Date,
  includeCurrent: boolean,
): Promise<PlannedTransition | null> {
  "use step";
  const row = await loadSchedule(installationID, scheduleID);
  if (!row || Number(row.revision) !== revision || !row.body.isEnabled) return null;
  return plannedTransition(row.body, revision, after, row.timezone, includeCurrent) ?? null;
}

async function executeTransition(
  installationID: string,
  transition: PlannedTransition,
): Promise<"applied" | "superseded"> {
  "use step";
  const row = await loadSchedule(installationID, transition.scheduleID);
  if (!row || Number(row.revision) !== transition.revision || !row.body.isEnabled) return "superseded";

  const stepStillExists = row.body.steps.some((step) => step.id === transition.stepID);
  if (!stepStillExists) return "superseded";
  const sql = getSql();
  try {
    await applyClimatePatch(installationID, transition.patch);
    await sql`
      INSERT INTO executions (installation_id, schedule_id, occurrence_id, step_id)
      VALUES (${installationID}, ${transition.scheduleID}, ${transition.occurrenceID}, ${transition.stepID})
      ON CONFLICT DO NOTHING
    `;
    await sql`
      UPDATE schedules
      SET last_execution_at = NOW(), last_status = 'applied', last_error = NULL
      WHERE installation_id = ${installationID} AND id = ${transition.scheduleID}
    `;
    return "applied";
  } catch (error) {
    const message = error instanceof Error ? error.message.slice(0, 500) : "Unknown climate command failure";
    await sql`
      UPDATE schedules
      SET last_execution_at = NOW(), last_status = 'retrying', last_error = ${message}
      WHERE installation_id = ${installationID} AND id = ${transition.scheduleID}
    `;
    if (message.includes("Unsupported") || message.includes("invalid device shadow")) {
      throw new FatalError(message);
    }
    throw error;
  }
}
