import { CatalogFacet } from "./catalog";
import reference from "./fixtures/referenceDiamond.json";
import { matchFacets } from "./matchFacets";
import { Address, Hex } from "viem";
import { describe, expect, it } from "vitest";
import { LoupeFacet } from "~~/utils/diamond/planCut";

const catalogFacet = (
  name: string,
  selectors: Hex[],
  { storage, touches = [] }: { storage?: string; touches?: string[] } = {},
): CatalogFacet => ({
  name,
  summary: `${name}'s summary.`,
  selectors: selectors.map(hex => ({ hex, signature: `${hex}()` })),
  ...(storage && { storage: { id: storage, slot: "0x00" } }),
  touches,
  release: { address: "0x0000000000000000000000000000000000000001", version: "0.2.0" },
});

// Selectors as the reference diamond on Hedera testnet serves them.
const GET_FEED = "0x280aebcf";
const LATEST_ANSWER = "0x084d4783";
const LATEST_ANSWER_RAW = "0xad0ddbee";
const REGISTER_FEED = "0x915d3063";
const UNREGISTER_FEED = "0x2a589908";
const DIAMOND_CUT = "0x1f931c1c";
const ACCESS_CONTROL: Hex[] = ["0x248a9ca3", "0x2f2ff15d", "0x91d14854", "0x36568abe", "0xd547741f"];
const EMERGENCY_STOP: Hex[] = [
  "0xa526d83b",
  "0x93c87f03",
  "0xb1e3268b",
  "0x0c68ba21",
  "0x3f683b6a",
  "0x71404156",
  "0x5b0b0c07",
];
const TOKEN_SALE_V2: Hex[] = [
  "0x08bf598d",
  "0xdf1d74ae",
  "0xed1bd76c",
  "0x8e3695b8",
  "0x1919fed7",
  "0x970ea83e",
  "0x404f21a5",
];

const chainlink = catalogFacet(
  "ChainlinkAdapter",
  [GET_FEED, LATEST_ANSWER, LATEST_ANSWER_RAW, REGISTER_FEED, UNREGISTER_FEED],
  {
    storage: "lattice.storage.ChainlinkAdapter",
    touches: ["lattice.storage.AccessControl"],
  },
);
const api3 = catalogFacet("API3Adapter", [GET_FEED, LATEST_ANSWER, LATEST_ANSWER_RAW, "0x99999999"]);
const accessControlDiamondCut = catalogFacet("AccessControlDiamondCut", [DIAMOND_CUT], {
  touches: ["lattice.storage.AccessControl", "lattice.storage.EmergencyStop"],
});
const diamondCutFacet = catalogFacet("DiamondCutFacet", [DIAMOND_CUT], { touches: ["diamond.lib.storage"] });
const emergencyStop = catalogFacet("EmergencyStop", EMERGENCY_STOP, {
  storage: "lattice.storage.EmergencyStop",
  touches: ["lattice.storage.AccessControl"],
});
const accessControl = catalogFacet("AccessControl", ACCESS_CONTROL, { storage: "lattice.storage.AccessControl" });

const catalog = [api3, chainlink, accessControlDiamondCut, emergencyStop, accessControl, diamondCutFacet];

let next = 0;
const mounted = (...functionSelectors: Hex[]) => ({
  facetAddress: `0x${(++next).toString(16).padStart(40, "0")}` as Address,
  functionSelectors,
});

describe("matchFacets", () => {
  it("recognizes a facet that serves exactly a catalog facet's selectors, in any order", () => {
    const facet = mounted(UNREGISTER_FEED, GET_FEED, REGISTER_FEED, LATEST_ANSWER_RAW, LATEST_ANSWER);

    expect(matchFacets([facet], catalog)).toEqual({
      recognized: [{ facet, catalog: chainlink, alsoMatches: [] }],
      ambiguous: [],
      partial: [],
      own: [],
    });
  });

  it("gives a tie between catalog facets with the same selectors to the one whose storage the other facets own", () => {
    const cut = mounted(DIAMOND_CUT);
    const roles = mounted(...ACCESS_CONTROL);
    const stop = mounted(...EMERGENCY_STOP);

    const { recognized, ambiguous } = matchFacets([cut, roles, stop], catalog);

    expect(ambiguous).toEqual([]);
    expect(recognized).toEqual([
      { facet: cut, catalog: accessControlDiamondCut, alsoMatches: ["DiamondCutFacet"] },
      { facet: roles, catalog: accessControl, alsoMatches: [] },
      { facet: stop, catalog: emergencyStop, alsoMatches: [] },
    ]);
  });

  it("leaves a tie that storage cannot break unresolved", () => {
    const cut = mounted(DIAMOND_CUT);

    expect(matchFacets([cut], catalog)).toEqual({
      recognized: [],
      ambiguous: [{ facet: cut, candidates: [accessControlDiamondCut, diamondCutFacet] }],
      partial: [],
      own: [],
    });
  });

  it("reports a facet that serves only some of a catalog facet's selectors as a partial match", () => {
    const facet = mounted(GET_FEED, LATEST_ANSWER, REGISTER_FEED, UNREGISTER_FEED);

    expect(matchFacets([facet], catalog).partial).toEqual([{ facet, closest: chainlink, shared: 4 }]);
  });

  it("reports a facet that serves a catalog facet's selectors and more as a partial match", () => {
    const facet = mounted(GET_FEED, LATEST_ANSWER, LATEST_ANSWER_RAW, REGISTER_FEED, UNREGISTER_FEED, TOKEN_SALE_V2[0]);

    expect(matchFacets([facet], catalog).partial).toEqual([{ facet, closest: chainlink, shared: 5 }]);
  });

  it("names the smaller catalog facet as closest when two share as many selectors", () => {
    const facet = mounted(GET_FEED, LATEST_ANSWER);

    expect(matchFacets([facet], catalog).partial).toEqual([{ facet, closest: api3, shared: 2 }]);
  });

  it("lists a facet that shares no selector with the catalog as the project's own", () => {
    const sale = mounted(...TOKEN_SALE_V2);

    expect(matchFacets([sale], catalog)).toEqual({ recognized: [], ambiguous: [], partial: [], own: [sale] });
  });

  it("ignores letter case in selectors", () => {
    const facet = mounted(...ACCESS_CONTROL.map(selector => selector.toUpperCase().replace("0X", "0x") as Hex));

    expect(matchFacets([facet], catalog).recognized).toEqual([{ facet, catalog: accessControl, alsoMatches: [] }]);
  });

  // The loupe of the reference diamond on Hedera testnet and the catalog entries it matches, read on 4 October 2026.
  it("names every Lattice facet of the reference diamond and leaves its sale as the project's own", () => {
    const loupe = reference.loupe as LoupeFacet[];
    const matches = matchFacets(loupe, reference.catalog.facets as CatalogFacet[]);

    expect(matches.recognized.map(match => [match.catalog.name, match.alsoMatches])).toEqual([
      ["ChainlinkAdapter", []],
      ["AccessControlDiamondCut", ["DiamondCutFacet"]],
      ["EmergencyStop", []],
      ["AccessControl", []],
      ["Receive", []],
      ["DiamondLoupeFacet", []],
      ["ERC165Facet", []],
      ["HTSAdapter", []],
    ]);
    expect(matches.ambiguous).toEqual([]);
    expect(matches.partial).toEqual([]);
    expect(matches.own).toEqual([loupe[8]]);
  });
});
