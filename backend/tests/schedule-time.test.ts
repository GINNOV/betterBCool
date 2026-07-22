import assert from "node:assert/strict";
import test from "node:test";
import { plannedTransition } from "../lib/schedule-time";
import type { ClimateSchedule } from "../lib/types";

const schedule: ClimateSchedule = {
  id: "night",
  name: "Night comfort",
  isEnabled: true,
  startMinutes: 22 * 60,
  weekdays: [1, 2, 3, 4, 5, 6, 7],
  steps: [
    { id: "cool", name: "Cool", patch: { powerEnabled: true, fanSpeed: "medium" }, durationMinutes: 120 },
    { id: "quiet", name: "Quiet", patch: { fanSpeed: "quiet" }, durationMinutes: 240 },
    { id: "off", name: "Off", patch: { powerEnabled: false }, durationMinutes: 30 },
    { id: "resume", name: "Resume", patch: { powerEnabled: true, fanSpeed: "quiet" } },
  ],
};

test("resolves an overnight current step", () => {
  const event = plannedTransition(schedule, 1, new Date("2026-07-21T04:10:00Z"), "UTC", true);
  assert.equal(event?.stepID, "off");
});

test("finds the next overnight step", () => {
  const event = plannedTransition(schedule, 1, new Date("2026-07-21T04:10:00Z"), "UTC", false);
  assert.equal(event?.stepID, "resume");
  assert.equal(event?.executeAt, "2026-07-21T04:30:00.000Z");
});

test("honors local time across daylight-saving offsets", () => {
  const event = plannedTransition(schedule, 1, new Date("2026-07-20T18:00:00Z"), "Europe/Rome", false);
  assert.equal(event?.executeAt, "2026-07-20T20:00:00.000Z");
});
