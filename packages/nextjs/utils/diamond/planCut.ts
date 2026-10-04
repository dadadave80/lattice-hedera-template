import { Address, Hex, isAddressEqual, size, slice, zeroAddress } from "viem";

/** EIP-2535 `FacetCutAction`. */
export const FacetCutAction = { Add: 0, Replace: 1, Remove: 2 } as const;

export type FacetCut = {
  facetAddress: Address;
  action: number;
  functionSelectors: Hex[];
};

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
