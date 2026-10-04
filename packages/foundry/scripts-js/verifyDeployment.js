// After a deploy to Hedera, verifies every contract it created on Sourcify, which HashScan reads for source.
// A contract that cannot be verified is reported with the command to retry it; it never fails the deploy.
import { spawn } from "child_process";
import { readFileSync, readdirSync } from "fs";
import { basename, dirname, join } from "path";
import { fileURLToPath } from "url";

const FOUNDRY_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SOURCIFY_API = "https://sourcify.dev/server/v2/contract";
const CONCURRENCY = 6;
const FORGE_TIMEOUT_MS = 180_000;
const CHECK_TIMEOUT_MS = 15_000;

const NETWORKS = {
  hedera_testnet: {
    chainId: 296,
    verifyCommand: "yarn foundry:verify:testnet",
  },
  hedera_mainnet: {
    chainId: 295,
    verifyCommand: "yarn foundry:verify:mainnet",
  },
};

/** The chain id to verify on, or null for a network that has no Sourcify to verify on. */
export function chainIdFor(network) {
  return NETWORKS[network]?.chainId ?? null;
}

/** The command that verifies one contract by hand. */
export function retryCommand(network, address, target) {
  return `${NETWORKS[network].verifyCommand} ${address} ${target}`;
}

/**
 * The contracts a deploy script created, in deployment order. A CALL's own address is its callee, so only
 * CREATE and CREATE2 transactions and what a call created (the diamond, inside LatticeFactory) are listed.
 *
 * @param record a `broadcast/<Script>/<chainId>/run-latest.json`
 */
export function createdContracts(record) {
  const seen = new Set();
  const contracts = [];
  const add = (name, address) => {
    if (!name || !address || seen.has(address.toLowerCase())) return;
    seen.add(address.toLowerCase());
    contracts.push({ name, address });
  };
  for (const transaction of record.transactions ?? []) {
    if (["CREATE", "CREATE2"].includes(transaction.transactionType)) {
      add(transaction.contractName, transaction.contractAddress);
    }
    for (const created of transaction.additionalContracts ?? []) {
      add(created.contractName, created.address);
    }
  }
  return contracts;
}

/**
 * The `<file>:<Contract>` that `forge verify-contract` takes, for the artifact built from the named
 * contract. Several `out/` directories can hold a file of the same name, so the match is on the artifact's
 * compilation target, not on where it sits. Null when no artifact matches.
 *
 * @param artifacts parsed Forge artifacts (`out/<File>.sol/<Name>.json`)
 */
export function compilationTargetFor(name, artifacts) {
  for (const artifact of artifacts) {
    const target = artifact?.metadata?.settings?.compilationTarget ?? {};
    const file = Object.keys(target).find((path) => target[path] === name);
    if (file) return `${file}:${name}`;
  }
  return null;
}

/** Why `forge verify-contract` failed: Sourcify's own message when it gave one, else forge's last line. */
export function failureReason(output) {
  const message = output.match(/^Message: `(.*)`$/m);
  if (message) return message[1];
  const lines = output.split("\n").filter((line) => line.trim());
  return lines.length
    ? lines[lines.length - 1].trim()
    : "forge printed nothing";
}

/**
 * The closing lines of a run: the tally, and for each failure the command to retry it.
 *
 * @param results `{ name, address, target, status, reason }` per contract, where status is `verified`,
 *   `already verified` or `failed`
 */
export function summaryLines(results, network) {
  const count = (status) =>
    results.filter((result) => result.status === status).length;
  const lines = [
    `Sourcify: ${count("verified")} verified, ${count(
      "already verified"
    )} already verified, ${count("failed")} failed.`,
  ];
  const failed = results.filter((result) => result.status === "failed");
  if (failed.length) {
    lines.push(
      "A failed verification does not affect the deploy. To retry one:",
      ...failed.map(
        (result) =>
          `  ${retryCommand(
            network,
            result.address,
            result.target ?? `<file>:${result.name}`
          )}`
      )
    );
  }
  return lines;
}

/** Maps `items` through `fn`, running at most `limit` calls at once. Results keep the order of `items`. */
export async function mapWithLimit(items, limit, fn) {
  const results = new Array(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const index = next++;
      results[index] = await fn(items[index], index);
    }
  };
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, worker)
  );
  return results;
}

/** True when Sourcify already has a match for the contract. An unverified one answers 404 with `match: null`. */
export async function isVerified(chainId, address) {
  const response = await fetch(`${SOURCIFY_API}/${chainId}/${address}`, {
    signal: AbortSignal.timeout(CHECK_TIMEOUT_MS),
  });
  const body = await response.json();
  return Boolean(body.match);
}

/**
 * Submits one contract to Sourcify through `forge verify-contract` and waits for the verdict. forge's output
 * is captured, because several of these run at once.
 *
 * @param target `<file>:<Contract>`, as in `yarn foundry:verify:testnet`
 * @param cwd the Foundry package, where the build artifacts are
 */
export function verifyContract({
  address,
  target,
  chainId,
  cwd = FOUNDRY_ROOT,
}) {
  return new Promise((resolve) => {
    let output = "";
    const forge = spawn(
      "forge",
      [
        "verify-contract",
        address,
        target,
        "--chain-id",
        String(chainId),
        "--verifier",
        "sourcify",
        "--watch",
      ],
      { cwd, stdio: ["ignore", "pipe", "pipe"], timeout: FORGE_TIMEOUT_MS }
    );
    forge.stdout.on("data", (chunk) => (output += chunk));
    forge.stderr.on("data", (chunk) => (output += chunk));
    forge.on("error", (error) => resolve({ ok: false, output: error.message }));
    forge.on("close", (code, signal) => {
      if (signal) {
        output += `\nforge timed out after ${FORGE_TIMEOUT_MS / 1000} s`;
      } else if (code !== 0 && !output.trim()) {
        output = `forge exited with ${code}`;
      }
      resolve({ ok: code === 0, output });
    });
  });
}

function artifactsNamed(outDir, name) {
  let files;
  try {
    files = readdirSync(outDir, { recursive: true });
  } catch {
    return [];
  }
  const named = files.filter(
    (file) =>
      basename(file) === `${name}.json` && !file.startsWith("build-info")
  );
  return named.flatMap((file) => {
    try {
      return [JSON.parse(readFileSync(join(outDir, file), "utf8"))];
    } catch {
      return [];
    }
  });
}

async function verifyOne(contract, { network, chainId, root, log }) {
  const { name, address } = contract;
  const target = compilationTargetFor(
    name,
    artifactsNamed(join(root, "out"), name)
  );
  const finish = (status, reason) => {
    const line = `  ${status.padEnd(16)} ${name} ${address}`;
    log(reason ? `${line}: ${reason}` : line);
    return { name, address, target, status, reason };
  };

  if (!target) return finish("failed", "no build artifact for this contract");
  try {
    if (await isVerified(chainId, address)) return finish("already verified");
  } catch (error) {
    log(
      `  Could not ask Sourcify about ${name} (${error.message}); submitting it anyway.`
    );
  }
  const { ok, output } = await verifyContract({
    address,
    target,
    chainId,
    cwd: root,
  });
  return ok ? finish("verified") : finish("failed", failureReason(output));
}

/**
 * Verifies every contract the deploy script created, skipping the ones Sourcify already has (Lattice
 * facets sit at deterministic addresses and are reused across deploys). Prints one line per contract and a
 * summary. Never throws: a problem is printed, and the deploy that called this is left as it was.
 *
 * @param network the `--network` that was deployed to
 * @param fileName the deploy script, e.g. `Deploy.s.sol`
 */
export async function verifyDeployment(
  network,
  fileName,
  { root = FOUNDRY_ROOT, log = console.log } = {}
) {
  const chainId = chainIdFor(network);
  if (chainId === null) return;

  try {
    const recordPath = join(
      "broadcast",
      basename(fileName),
      String(chainId),
      "run-latest.json"
    );
    let record;
    try {
      record = JSON.parse(readFileSync(join(root, recordPath), "utf8"));
    } catch {
      log(
        `\nWarning: no readable ${recordPath}, so nothing was verified on Sourcify. To verify a contract by hand:\n  ${retryCommand(
          network,
          "<address>",
          "<file>:<Contract>"
        )}`
      );
      return;
    }

    const contracts = createdContracts(record);
    if (!contracts.length) return;
    log(
      `\nVerifying ${contracts.length} contract${
        contracts.length === 1 ? "" : "s"
      } on Sourcify, which HashScan reads for source...`
    );
    const results = await mapWithLimit(contracts, CONCURRENCY, (contract) =>
      verifyOne(contract, { network, chainId, root, log })
    );
    log(`\n${summaryLines(results, network).join("\n")}\n`);
  } catch (error) {
    log(
      `\nWarning: could not verify the deployment on Sourcify: ${error.message}`
    );
  }
}
