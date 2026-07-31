import assert from "node:assert/strict";
import test from "node:test";
import { validatePatch } from "../lib/bosch";
import type { InstallationRow } from "../lib/db";

function installation(transport: InstallationRow["transport"]): InstallationRow {
  return {
    id: "test-installation",
    token_ciphertext: "unused",
    token_version: "1",
    gateway_id: "test-gateway",
    transport,
    region: "euc1",
  };
}

test("HomeCom accepts half-degree temperature setpoints", () => {
  assert.doesNotThrow(() => validatePatch(
    { temperatureSetpoint: 24.5 },
    installation("bacon"),
  ));
});

test("HomeCom still rejects unsupported fractional setpoints", () => {
  assert.throws(
    () => validatePatch({ temperatureSetpoint: 24.25 }, installation("bacon")),
    /Unsupported temperature setpoint/,
  );
});
