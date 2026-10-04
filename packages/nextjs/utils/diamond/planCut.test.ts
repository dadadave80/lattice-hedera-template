import {
  FacetCut,
  FacetCutAction,
  LoupeFacet,
  knownContractName,
  leftOnOutgoingFacets,
  outgoingFacets,
  planCut,
  selectorsOutsideSale,
  unpackSelectors,
} from "./planCut";
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

const BUY = "0x08bf598d";
const QUOTE = "0xed1bd76c";
const BONUS_BPS = "0x404f21a5";
const DIAMOND_CUT = "0x1f931c1c";
const SALE_FACET = "0x3333333333333333333333333333333333333333";
const CUT_FACET = "0x4444444444444444444444444444444444444444";

const replace = (...functionSelectors: `0x${string}`[]): FacetCut => ({
  facetAddress: NEW_FACET,
  action: FacetCutAction.Replace,
  functionSelectors,
});
const add = (...functionSelectors: `0x${string}`[]): FacetCut => ({
  facetAddress: NEW_FACET,
  action: FacetCutAction.Add,
  functionSelectors,
});

describe("knownContractName", () => {
  const deployed = {
    Diamond: { address: "0xAbCdEf0000000000000000000000000000000001" },
    TokenSaleV2: { address: NEW_FACET },
  };

  it("names the deployed contract at the address", () => {
    expect(knownContractName(NEW_FACET, deployed)).toBe("TokenSaleV2");
  });

  it("matches regardless of letter case", () => {
    expect(knownContractName("0xabcdef0000000000000000000000000000000001", deployed)).toBe("Diamond");
    expect(knownContractName("0xABCDEF0000000000000000000000000000000001", deployed)).toBe("Diamond");
  });

  it("returns nothing for an address that is not a deployment", () => {
    expect(knownContractName(OLD_FACET, deployed)).toBeUndefined();
  });

  it("returns nothing when the network has no deployments", () => {
    expect(knownContractName(OLD_FACET, undefined)).toBeUndefined();
  });
});

describe("outgoingFacets", () => {
  const facets = [
    { facetAddress: OLD_FACET, functionSelectors: [BUY, QUOTE, BONUS_BPS] },
    { facetAddress: CUT_FACET, functionSelectors: [DIAMOND_CUT] },
  ] as const;

  it("groups the replaced selectors by the facet that serves them today", () => {
    const cuts = [replace(BUY, DIAMOND_CUT), add("0x11111111")];

    expect(outgoingFacets(cuts, facets)).toEqual([
      { facetAddress: OLD_FACET, functionSelectors: [BUY] },
      { facetAddress: CUT_FACET, functionSelectors: [DIAMOND_CUT] },
    ]);
  });

  it("takes nothing from any facet when the plan only adds", () => {
    expect(outgoingFacets([add(BONUS_BPS)], facets)).toEqual([]);
  });
});

describe("selectorsOutsideSale", () => {
  const facets = [
    { facetAddress: SALE_FACET, functionSelectors: [BUY, QUOTE] },
    { facetAddress: CUT_FACET, functionSelectors: [DIAMOND_CUT, "0x2f2ff15d"] },
  ] as const;

  it("accepts replacing the sale's own functions and adding a new one", () => {
    expect(selectorsOutsideSale([replace(BUY, QUOTE), add(BONUS_BPS)], facets)).toEqual([]);
  });

  it("flags a selector the diamond routes to a facet other than the sale's", () => {
    expect(selectorsOutsideSale([replace(BUY, "0x2f2ff15d")], facets)).toEqual(["0x2f2ff15d"]);
  });

  it("flags replacing diamondCut", () => {
    expect(selectorsOutsideSale([replace(DIAMOND_CUT)], facets)).toEqual([DIAMOND_CUT]);
  });

  it("flags adding diamondCut", () => {
    expect(selectorsOutsideSale([add(DIAMOND_CUT)], [facets[0]])).toEqual([DIAMOND_CUT]);
  });

  it("flags every replaced selector when no facet serves buy", () => {
    expect(selectorsOutsideSale([replace(QUOTE)], [{ facetAddress: OLD_FACET, functionSelectors: [QUOTE] }])).toEqual([
      QUOTE,
    ]);
  });
});

describe("leftOnOutgoingFacets", () => {
  const v2Mounted: LoupeFacet = { facetAddress: OLD_FACET, functionSelectors: [BUY, QUOTE, BONUS_BPS] };
  const v1Mounted: LoupeFacet = { facetAddress: OLD_FACET, functionSelectors: [BUY, QUOTE] };

  it("lists what an outgoing facet still serves that the new facet does not export, such as bonusBps when V1 replaces V2", () => {
    expect(leftOnOutgoingFacets([replace(BUY, QUOTE)], [v2Mounted])).toEqual([
      { facetAddress: OLD_FACET, functionSelectors: [BONUS_BPS] },
    ]);
  });

  it("lists nothing when the new facet takes over everything the outgoing facet serves", () => {
    expect(leftOnOutgoingFacets([replace(BUY, QUOTE)], [v1Mounted])).toEqual([]);
  });

  it("lists nothing when the plan replaces nothing", () => {
    expect(leftOnOutgoingFacets([add(BONUS_BPS)], [v1Mounted])).toEqual([]);
  });

  it("leaves out a facet that loses no selector", () => {
    const bystander: LoupeFacet = { facetAddress: CUT_FACET, functionSelectors: [DIAMOND_CUT] };

    expect(leftOnOutgoingFacets([replace(BUY)], [v2Mounted, bystander])).toEqual([
      { facetAddress: OLD_FACET, functionSelectors: [QUOTE, BONUS_BPS] },
    ]);
  });

  it("reports each outgoing facet on its own", () => {
    const other: LoupeFacet = { facetAddress: SALE_FACET, functionSelectors: ["0x2f2ff15d", "0x11111111"] };

    expect(leftOnOutgoingFacets([replace(BUY, "0x2f2ff15d")], [v2Mounted, other])).toEqual([
      { facetAddress: OLD_FACET, functionSelectors: [QUOTE, BONUS_BPS] },
      { facetAddress: SALE_FACET, functionSelectors: ["0x11111111"] },
    ]);
  });
});
