import { test } from "node:test";
import assert from "node:assert/strict";
import { mergeDiamondAbi, signatureOf } from "./diamondAbi.js";

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
