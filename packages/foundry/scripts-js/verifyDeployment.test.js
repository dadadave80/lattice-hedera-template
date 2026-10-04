import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import {
  chainIdFor,
  compilationTargetFor,
  createdContracts,
  failureReason,
  mapWithLimit,
  retryCommand,
  summaryLines,
  verifyDeployment,
} from "./verifyDeployment.js";

// Shaped like broadcast/<Script>/<chainId>/run-latest.json: a CALL's contractAddress is the callee, and the
// diamond a factory creates shows up only under that call's additionalContracts.
const record = {
  transactions: [
    {
      transactionType: "CREATE2",
      contractName: "ChainlinkAdapter",
      contractAddress: "0xada0b395f78ec98322b737af1fb6eab14106c4df",
      additionalContracts: [],
    },
    {
      transactionType: "CREATE",
      contractName: "TokenSale",
      contractAddress: "0xa454565d6c9cea8cf1c9be93ed87237b6a935c84",
      additionalContracts: [],
    },
    {
      transactionType: "CREATE",
      contractName: "LatticeFactory",
      contractAddress: "0x0e9a34020282f3645768d2b553c61b906071b51d",
      additionalContracts: [],
    },
    {
      transactionType: "CALL",
      contractName: "LatticeFactory",
      contractAddress: "0x0e9a34020282f3645768d2b553c61b906071b51d",
      additionalContracts: [
        {
          transactionType: "CREATE2",
          contractName: "Lattice",
          address: "0x4eb94355872ab90ab258b940ee98b706dc9b2aa9",
        },
        {
          transactionType: "CREATE",
          contractName: null,
          address: "0x1111111111111111111111111111111111111111",
        },
      ],
    },
    {
      transactionType: "CALL",
      contractName: "Lattice",
      contractAddress: "0x4eb94355872ab90ab258b940ee98b706dc9b2aa9",
      additionalContracts: [],
    },
    {
      transactionType: "CREATE",
      contractName: null,
      contractAddress: "0x2222222222222222222222222222222222222222",
      additionalContracts: [],
    },
    {
      transactionType: "CREATE2",
      contractName: "ChainlinkAdapter",
      contractAddress: "0xADA0B395F78EC98322B737AF1FB6EAB14106C4DF",
      additionalContracts: [],
    },
  ],
};

test("lists what a deploy created, in deployment order", () => {
  assert.deepEqual(createdContracts(record), [
    {
      name: "ChainlinkAdapter",
      address: "0xada0b395f78ec98322b737af1fb6eab14106c4df",
    },
    {
      name: "TokenSale",
      address: "0xa454565d6c9cea8cf1c9be93ed87237b6a935c84",
    },
    {
      name: "LatticeFactory",
      address: "0x0e9a34020282f3645768d2b553c61b906071b51d",
    },
    {
      name: "Lattice",
      address: "0x4eb94355872ab90ab258b940ee98b706dc9b2aa9",
    },
  ]);
});

test("a call creates nothing of its own, and a record with no transactions lists nothing", () => {
  const calls = {
    transactions: [
      {
        transactionType: "CALL",
        contractName: "Lattice",
        contractAddress: "0x4eb94355872ab90ab258b940ee98b706dc9b2aa9",
        additionalContracts: [],
      },
      {
        transactionType: "CALL",
        contractName: "Lattice",
        contractAddress: "0x4eb94355872ab90ab258b940ee98b706dc9b2aa9",
      },
    ],
  };
  assert.deepEqual(createdContracts(calls), []);
  assert.deepEqual(createdContracts({}), []);
});

const artifact = (compilationTarget) => ({
  metadata: { settings: { compilationTarget } },
});

test("finds the compilation target of the artifact that is built from the named contract", () => {
  // Two out/ directories hold a Token.json; only one of them is the Token contract.
  const artifacts = [
    artifact({ "lib/other/Token.sol": "TokenLike" }),
    artifact({ "contracts/Token.sol": "Token" }),
  ];
  assert.equal(
    compilationTargetFor("Token", artifacts),
    "contracts/Token.sol:Token"
  );
});

test("has no compilation target when no artifact matches", () => {
  assert.equal(compilationTargetFor("Token", []), null);
  assert.equal(
    compilationTargetFor("Token", [
      artifact({ "contracts/Other.sol": "Other" }),
      {},
    ]),
    null
  );
});

test("verifies only on the Hedera networks", () => {
  assert.equal(chainIdFor("hedera_testnet"), 296);
  assert.equal(chainIdFor("hedera_mainnet"), 295);
  assert.equal(chainIdFor("localhost"), null);
  assert.equal(chainIdFor("constructor"), null);
});

test("prints the command that verifies one contract by hand", () => {
  assert.equal(
    retryCommand(
      "hedera_testnet",
      "0xabc",
      "contracts/TokenSale.sol:TokenSale"
    ),
    "yarn foundry:verify:testnet 0xabc contracts/TokenSale.sol:TokenSale"
  );
  assert.equal(
    retryCommand(
      "hedera_mainnet",
      "0xabc",
      "contracts/TokenSale.sol:TokenSale"
    ),
    "yarn foundry:verify:mainnet 0xabc contracts/TokenSale.sol:TokenSale"
  );
});

test("takes the reason from Sourcify's message, else from the last line", () => {
  const rejected = [
    "Start verifying contract `0x8932` deployed on 296",
    "Error: Checking verification result failed",
    "",
    "Context:",
    "- Verification job failed:",
    "Error Code: `bytecode_length_mismatch`",
    "Message: `The recompiled bytecode length doesn't match the onchain bytecode length.`",
    "",
  ].join("\n");
  assert.equal(
    failureReason(rejected),
    "The recompiled bytecode length doesn't match the onchain bytecode length."
  );
  assert.equal(
    failureReason("Compiling...\nError: could not reach sourcify.dev\n"),
    "Error: could not reach sourcify.dev"
  );
  assert.equal(failureReason(""), "forge printed nothing");
});

test("sums up a run and lists the command to retry each failure", () => {
  const results = [
    {
      name: "A",
      address: "0xa",
      target: "contracts/A.sol:A",
      status: "verified",
    },
    {
      name: "B",
      address: "0xb",
      target: "contracts/B.sol:B",
      status: "already verified",
    },
    {
      name: "C",
      address: "0xc",
      target: "contracts/C.sol:C",
      status: "failed",
      reason: "boom",
    },
    {
      name: "D",
      address: "0xd",
      target: null,
      status: "failed",
      reason: "no artifact",
    },
  ];
  const lines = summaryLines(results, "hedera_testnet");
  assert.match(lines[0], /1 verified, 1 already verified, 2 failed/);
  const text = lines.join("\n");
  assert.match(text, /does not affect the deploy/);
  assert.match(text, /yarn foundry:verify:testnet 0xc contracts\/C\.sol:C/);
  assert.match(text, /yarn foundry:verify:testnet 0xd <file>:D/);
  assert.doesNotMatch(text, /0xa /);
});

test("sums up a clean run in one line", () => {
  const lines = summaryLines(
    [{ name: "A", address: "0xa", target: "x:A", status: "verified" }],
    "hedera_mainnet"
  );
  assert.equal(lines.length, 1);
  assert.match(lines[0], /1 verified, 0 already verified, 0 failed/);
});

test("runs at most the given number at once and keeps results in order", async () => {
  let running = 0;
  let peak = 0;
  const results = await mapWithLimit([1, 2, 3, 4, 5, 6, 7], 3, async (n) => {
    running++;
    peak = Math.max(peak, running);
    await new Promise((resolve) => setTimeout(resolve, 5 * (8 - n)));
    running--;
    return n * 10;
  });
  assert.deepEqual(results, [10, 20, 30, 40, 50, 60, 70]);
  assert.equal(peak, 3);
  assert.deepEqual(await mapWithLimit([], 3, async (n) => n), []);
});

test("warns instead of failing when there is no broadcast record", async () => {
  const root = mkdtempSync(join(tmpdir(), "verify-deployment-"));
  try {
    const logged = [];
    await verifyDeployment("hedera_testnet", "Deploy.s.sol", {
      root,
      log: (line) => logged.push(line),
    });
    assert.equal(logged.length, 1);
    assert.match(logged[0], /Warning/);
    assert.match(logged[0], /broadcast\/Deploy\.s\.sol\/296\/run-latest\.json/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("does nothing off Hedera", async () => {
  const logged = [];
  await verifyDeployment("localhost", "Deploy.s.sol", {
    log: (line) => logged.push(line),
  });
  assert.deepEqual(logged, []);
});
