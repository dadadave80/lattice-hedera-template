import { test } from "node:test";
import assert from "node:assert/strict";
import {
  isPlumbing,
  mergeDiamondAbi,
  signatureOf,
  withDiamond,
} from "./diamondAbi.js";

const fn = (name, inputs = []) => ({
  type: "function",
  name,
  inputs,
  outputs: [],
  stateMutability: "nonpayable",
});
const event = (name) => ({ type: "event", name, inputs: [], anonymous: false });

test("signatureOf expands tuples the way Solidity does", () => {
  const diamondCut = fn("diamondCut", [
    {
      name: "_diamondCut",
      type: "tuple[]",
      components: [
        { name: "facetAddress", type: "address" },
        { name: "action", type: "uint8" },
        { name: "functionSelectors", type: "bytes4[]" },
      ],
    },
    { name: "_init", type: "address" },
    { name: "_calldata", type: "bytes" },
  ]);

  assert.equal(
    signatureOf(diamondCut),
    "diamondCut((address,uint8,bytes4[])[],address,bytes)"
  );
});

test("mergeDiamondAbi keeps only the functions each facet serves", () => {
  const oracle = {
    abi: [
      fn("latestAnswer", [{ name: "key", type: "bytes32" }]),
      fn("unregisterFeed", [{ name: "key", type: "bytes32" }]),
      fn("exportSelectors"),
      event("FeedRegistered"),
    ],
    methodIdentifiers: {
      "latestAnswer(bytes32)": "084d4783",
      "unregisterFeed(bytes32)": "2a589908",
      "exportSelectors()": "0ef22643",
    },
    selectors: ["0x084D4783"], // unregisterFeed was excluded by the recipe
  };

  const names = mergeDiamondAbi([oracle]).map((entry) => entry.name);

  assert.deepEqual(names, ["latestAnswer", "FeedRegistered"]);
});

test("mergeDiamondAbi lists an event or error shared by two facets once", () => {
  const facet = (selector, name) => ({
    abi: [fn(name), event("RoleGranted")],
    methodIdentifiers: { [`${name}()`]: selector },
    selectors: [`0x${selector}`],
  });

  const merged = mergeDiamondAbi([
    facet("aaaaaaaa", "pause"),
    facet("bbbbbbbb", "unpause"),
  ]);

  assert.deepEqual(
    merged.map((entry) => entry.name),
    ["pause", "RoleGranted", "unpause"]
  );
});

test("mergeDiamondAbi drops constructors", () => {
  const facet = {
    abi: [{ type: "constructor", inputs: [] }, { type: "receive" }],
    methodIdentifiers: {},
    selectors: ["0x00000000"],
  };

  assert.deepEqual(mergeDiamondAbi([facet]), [{ type: "receive" }]);
});

test("isPlumbing hides deploy helpers, initializers and the diamond's own facets", () => {
  const facets = ["HTSAdapter", "TokenSale"];

  assert.equal(isPlumbing("LatticeFactory", facets), true);
  assert.equal(isPlumbing("TokenSaleInit", facets), true);
  assert.equal(isPlumbing("TokenSale", facets), true);
  assert.equal(isPlumbing("TokenSaleV2", facets), false);
});

test("withDiamond gives the chain one Diamond and keeps what was deployed on its own", () => {
  const artifacts = {
    TokenSale: {
      abi: [fn("buy"), event("TokensPurchased")],
      methodIdentifiers: { "buy()": "08bf598d" },
    },
  };
  const record = {
    address: "0xD1a0000000000000000000000000000000000000",
    deployedOnBlock: 42,
    facets: ["TokenSale"],
    selectors: { TokenSale: ["0x08bf598d"] },
  };
  const broadcast = {
    TokenSale: { address: "0x1" },
    TokenSaleInit: { address: "0x2" },
    LatticeFactory: { address: "0x3" },
    TokenSaleV2: { address: "0x4" },
  };

  const contracts = withDiamond(broadcast, record, (name) => artifacts[name]);

  assert.deepEqual(Object.keys(contracts), ["Diamond", "TokenSaleV2"]);
  assert.deepEqual(contracts.Diamond, {
    address: record.address,
    abi: artifacts.TokenSale.abi,
    inheritedFunctions: {},
    deployedOnBlock: 42,
  });
});

test("withDiamond names the file a facet's artifact should be in when it is missing", () => {
  const record = {
    address: "0xD1a0000000000000000000000000000000000000",
    deployedOnBlock: 42,
    facets: ["Referral"],
    selectors: { Referral: ["0x12345678"] },
  };
  const missingFile = () => {
    throw Object.assign(new Error("ENOENT: no such file"), { code: "ENOENT" });
  };

  for (const artifactOf of [() => null, missingFile]) {
    assert.throws(
      () => withDiamond({}, record, artifactOf),
      /out\/Referral\.sol\/Referral\.json does not exist\. Put Referral in contracts\/Referral\.sol/
    );
  }
});

test("withDiamond passes on any other error reading an artifact", () => {
  const record = {
    address: "0xD1a0000000000000000000000000000000000000",
    deployedOnBlock: 42,
    facets: ["TokenSale"],
    selectors: { TokenSale: ["0x08bf598d"] },
  };
  const corrupt = () => {
    throw new SyntaxError("Unexpected end of JSON input");
  };

  assert.throws(() => withDiamond({}, record, corrupt), SyntaxError);
});
