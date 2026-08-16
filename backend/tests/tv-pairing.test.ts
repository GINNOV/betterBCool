import assert from "node:assert/strict";
import test from "node:test";
import {
  generatePairingCode,
  generatePollingSecret,
  hashSecret,
  normalizePairingCode,
  normalizeTVName,
  safeSecretEqual,
} from "../lib/tv-pairing";

test("pairing codes are six digits and normalize pasted formatting", () => {
  const code = generatePairingCode();
  assert.match(code, /^\d{6}$/);
  assert.equal(normalizePairingCode(` ${code.slice(0, 3)}-${code.slice(3)} `), code);
  assert.equal(normalizePairingCode("12-34"), "1234");
});

test("TV secrets are high-entropy, one-way values", () => {
  const secret = generatePollingSecret();
  assert.ok(secret.length >= 40);
  assert.notEqual(secret, hashSecret(secret));
  assert.equal(safeSecretEqual(hashSecret(secret), hashSecret(secret)), true);
  assert.equal(safeSecretEqual(hashSecret(secret), hashSecret(`${secret}x`)), false);
});

test("TV names are bounded and have a useful fallback", () => {
  assert.equal(normalizeTVName("  Lounge   TV  "), "Lounge TV");
  assert.equal(normalizeTVName(""), "Living Room TV");
  assert.equal(normalizeTVName(undefined), "Living Room TV");
  assert.equal(normalizeTVName("x".repeat(100)).length, 64);
});
