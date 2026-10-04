// Forge 1.8 asks Hedera's JSON-RPC relay for account state by block hash (EIP-1898). The relay only accepts
// a block number or tag, so `forge script` fails before it sends anything. Forge 1.7.1 is unaffected.
// Tracked in https://github.com/hiero-ledger/hiero-json-rpc-relay/issues/5826.
const FIRST_AFFECTED = [1, 8, 0];

/**
 * A warning to print before deploying, or null when there is nothing to warn about.
 *
 * @param forgeVersionOutput what `forge --version` printed
 * @param network the `--network` being deployed to
 */
export function relayWarning(forgeVersionOutput, network) {
  if (!network.startsWith("hedera_")) return null;
  const match = forgeVersionOutput.match(/(\d+)\.(\d+)\.(\d+)/);
  if (!match) return null;

  const version = match.slice(1).map(Number);
  for (let i = 0; i < FIRST_AFFECTED.length; i++) {
    if (version[i] > FIRST_AFFECTED[i]) break;
    if (version[i] < FIRST_AFFECTED[i]) return null;
  }

  return [
    `Warning: forge ${version.join(".")} may not be able to deploy to Hedera.`,
    "   If the deploy stops with `-32602 Invalid parameter 1`, switch to Foundry 1.7.1 and run it again:",
    "     foundryup --install v1.7.1",
    "   Details: https://github.com/hiero-ledger/hiero-json-rpc-relay/issues/5826",
  ].join("\n");
}
