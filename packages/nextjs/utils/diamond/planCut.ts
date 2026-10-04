import { Address, Hex, isAddressEqual, size, slice, zeroAddress } from "viem";

/** EIP-2535 `FacetCutAction`. */
export const FacetCutAction = { Add: 0, Replace: 1, Remove: 2 } as const;

export type FacetCut = {
  facetAddress: Address;
  action: number;
  functionSelectors: Hex[];
};

/** One row of the loupe's `facets()`: a facet address and the selectors the diamond routes to it. */
export type LoupeFacet = { facetAddress: Address; functionSelectors: readonly Hex[] };

/** `buy(int64)`: the function that tells which facet is the sale. */
const BUY_SELECTOR = "0x08bf598d";

/** `diamondCut(...)`: whoever serves it controls every future upgrade. */
const DIAMOND_CUT_SELECTOR = "0x1f931c1c";

/** Splits the bytes a facet returns from ERC-8153 `exportSelectors()` into its 4-byte selectors. */
export function unpackSelectors(packed: Hex): Hex[] {
  const count = size(packed) / 4;
  if (!Number.isInteger(count)) throw new Error("exportSelectors() must return a whole number of 4-byte selectors");
  return Array.from({ length: count }, (_, index) => slice(packed, index * 4, index * 4 + 4));
}

/**
 * The cuts that mount `facet` on a diamond: a selector the diamond already routes is replaced, a new one is
 * added, and one that already points at `facet` is left alone.
 *
 * @param selectors what the facet exports
 * @param routes where the diamond routes each of those selectors today (`facetAddress(selector)`), index-aligned
 */
export function planCut(facet: Address, selectors: Hex[], routes: Address[]): FacetCut[] {
  const add = selectors.filter((_, index) => isAddressEqual(routes[index], zeroAddress));
  const replace = selectors.filter(
    (_, index) => !isAddressEqual(routes[index], zeroAddress) && !isAddressEqual(routes[index], facet),
  );
  const cuts: FacetCut[] = [];
  if (replace.length > 0)
    cuts.push({ facetAddress: facet, action: FacetCutAction.Replace, functionSelectors: replace });
  if (add.length > 0) cuts.push({ facetAddress: facet, action: FacetCutAction.Add, functionSelectors: add });
  return cuts;
}

/** The name of the contract in `deployed` at `address`, ignoring letter case, if this project deployed it. */
export function knownContractName(address: Address, deployed?: Record<string, { address: string }>) {
  return Object.entries(deployed ?? {}).find(
    ([, contract]) => contract.address.toLowerCase() === address.toLowerCase(),
  )?.[0];
}

/** The facets a plan takes selectors from, each with the selectors it loses. */
export function outgoingFacets(cuts: FacetCut[], facets: readonly LoupeFacet[]): LoupeFacet[] {
  const replaced = new Set(
    cuts.filter(cut => cut.action === FacetCutAction.Replace).flatMap(cut => cut.functionSelectors),
  );
  return facets
    .map(facet => ({ ...facet, functionSelectors: facet.functionSelectors.filter(selector => replaced.has(selector)) }))
    .filter(facet => facet.functionSelectors.length > 0);
}

/**
 * The planned selectors that are not part of the sale: any the diamond routes to a facet other than the one that
 * serves `buy(int64)`, and an Add of `diamondCut`. A facet that takes these over takes over the diamond.
 */
export function selectorsOutsideSale(cuts: FacetCut[], facets: readonly LoupeFacet[]): Hex[] {
  const saleFacet = facets.find(facet => facet.functionSelectors.includes(BUY_SELECTOR))?.facetAddress;
  const outside = outgoingFacets(cuts, facets)
    .filter(facet => !saleFacet || !isAddressEqual(facet.facetAddress, saleFacet))
    .flatMap(facet => facet.functionSelectors);
  const addsDiamondCut = cuts.some(
    cut => cut.action === FacetCutAction.Add && cut.functionSelectors.includes(DIAMOND_CUT_SELECTOR),
  );
  return addsDiamondCut ? [...outside, DIAMOND_CUT_SELECTOR] : outside;
}
