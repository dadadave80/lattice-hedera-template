import { FacetCutAction, planCut, unpackSelectors } from "./planCut";
import { zeroAddress } from "viem";
import { describe, expect, it } from "vitest";

const OLD_FACET = "0x1111111111111111111111111111111111111111";
const NEW_FACET = "0x2222222222222222222222222222222222222222";

describe("unpackSelectors", () => {
  it("splits packed bytes into 4-byte selectors", () => {
    expect(unpackSelectors("0x08bf598ded1bd76c404f21a5")).toEqual(["0x08bf598d", "0xed1bd76c", "0x404f21a5"]);
  });

  it("returns nothing for empty bytes", () => {
    expect(unpackSelectors("0x")).toEqual([]);
  });

  it("rejects bytes that are not a whole number of selectors", () => {
    expect(() => unpackSelectors("0x08bf598ded")).toThrow("whole number of 4-byte selectors");
  });
});

describe("planCut", () => {
  it("replaces selectors the diamond already routes and adds the new ones", () => {
    const cuts = planCut(NEW_FACET, ["0x08bf598d", "0xed1bd76c", "0x404f21a5"], [OLD_FACET, OLD_FACET, zeroAddress]);

    expect(cuts).toEqual([
      { facetAddress: NEW_FACET, action: FacetCutAction.Replace, functionSelectors: ["0x08bf598d", "0xed1bd76c"] },
      { facetAddress: NEW_FACET, action: FacetCutAction.Add, functionSelectors: ["0x404f21a5"] },
    ]);
  });

  it("leaves out an action with no selectors", () => {
    const cuts = planCut(NEW_FACET, ["0x404f21a5"], [zeroAddress]);

    expect(cuts).toEqual([{ facetAddress: NEW_FACET, action: FacetCutAction.Add, functionSelectors: ["0x404f21a5"] }]);
  });

  it("plans nothing for a facet that is already mounted", () => {
    expect(planCut(NEW_FACET, ["0x08bf598d"], [NEW_FACET])).toEqual([]);
  });
});
