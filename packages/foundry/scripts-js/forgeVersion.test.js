import { test } from "node:test";
import assert from "node:assert/strict";
import { relayWarning } from "./forgeVersion.js";

const forge = (version) =>
  `forge Version: ${version}\nCommit SHA: 982849d3140c01fd3b72905759581a132df7aa98`;

test("warns when forge 1.8 or newer deploys to Hedera", () => {
  assert.match(relayWarning(forge("1.8.1"), "hedera_testnet"), /forge 1\.8\.1/);
  assert.match(relayWarning(forge("1.8.0"), "hedera_mainnet"), /v1\.7\.1/);
  assert.match(relayWarning(forge("2.0.0"), "hedera_testnet"), /forge 2\.0\.0/);
});

test("stays quiet for a forge that can reach the relay", () => {
  assert.equal(relayWarning(forge("1.7.1"), "hedera_testnet"), null);
  assert.equal(relayWarning(forge("1.5.1-stable"), "hedera_testnet"), null);
});

test("stays quiet off Hedera and when the version cannot be read", () => {
  assert.equal(relayWarning(forge("1.8.1"), "localhost"), null);
  assert.equal(relayWarning("", "hedera_testnet"), null);
});
