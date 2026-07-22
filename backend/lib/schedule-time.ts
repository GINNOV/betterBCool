import { DateTime } from "luxon";
import type { ClimateSchedule, PlannedTransition } from "./types";

export function transitionsAround(
  schedule: ClimateSchedule,
  revision: number,
  instant: Date,
  timezone: string,
): PlannedTransition[] {
  const center = DateTime.fromJSDate(instant, { zone: timezone });
  if (!center.isValid) throw new Error("Invalid schedule timezone");
  const firstDay = center.startOf("day").minus({ days: 7 });
  const events: PlannedTransition[] = [];

  for (let dayOffset = 0; dayOffset <= 15; dayOffset += 1) {
    const day = firstDay.plus({ days: dayOffset });
    const swiftWeekday = day.weekday % 7 + 1;
    if (!schedule.weekdays.includes(swiftWeekday)) continue;
    let eventTime = day.startOf("day").plus({ minutes: schedule.startMinutes });
    for (const step of schedule.steps) {
      events.push({
        occurrenceID: `${day.toISODate()}-${schedule.id}`,
        scheduleID: schedule.id,
        revision,
        stepID: step.id,
        executeAt: eventTime.toUTC().toISO()!,
        patch: step.patch,
      });
      if (!step.durationMinutes || step.durationMinutes <= 0) break;
      eventTime = eventTime.plus({ minutes: step.durationMinutes });
    }
  }
  return events.sort((left, right) => left.executeAt.localeCompare(right.executeAt));
}

export function plannedTransition(
  schedule: ClimateSchedule,
  revision: number,
  after: Date,
  timezone: string,
  includeCurrent: boolean,
): PlannedTransition | undefined {
  const events = transitionsAround(schedule, revision, after, timezone);
  const timestamp = after.getTime();
  if (includeCurrent) {
    return events.filter((event) => new Date(event.executeAt).getTime() <= timestamp).at(-1);
  }
  return events.find((event) => new Date(event.executeAt).getTime() > timestamp);
}
