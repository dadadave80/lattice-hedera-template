import { CatalogFacet } from "./catalog";
import { LoupeFacet } from "~~/utils/diamond/planCut";

export type FacetMatches = {
  /**
   * Facets that serve exactly a catalog facet's selectors. `alsoMatches` names catalog facets with the same
   * selectors that lost the tie on storage.
   */
  recognized: { facet: LoupeFacet; catalog: CatalogFacet; alsoMatches: string[] }[];
  /** Facets that serve exactly the selectors of several catalog facets, with nothing to choose between them. */
  ambiguous: { facet: LoupeFacet; candidates: CatalogFacet[] }[];
  /** Facets that share some selectors with the catalog, but not exactly one facet's: `closest` shares the most. */
  partial: { facet: LoupeFacet; closest: CatalogFacet; shared: number }[];
  /** Facets that share no selector with the catalog. */
  own: LoupeFacet[];
};

const selectorSet = (selectors: readonly string[]) => new Set(selectors.map(selector => selector.toLowerCase()));

const catalogSelectors = (facet: CatalogFacet) => selectorSet(facet.selectors.map(selector => selector.hex));

const sameSet = (a: Set<string>, b: Set<string>) => a.size === b.size && [...a].every(selector => b.has(selector));

const sharedCount = (a: Set<string>, b: Set<string>) => [...a].filter(selector => b.has(selector)).length;

/**
 * Names each facet of a diamond from Studio's catalog by its selectors. A deployed facet's code differs from
 * Lattice's release whenever it was compiled with other settings, so selectors are all that can be compared.
 * Catalog facets with the same selectors (`AccessControlDiamondCut` and `DiamondCutFacet` both serve only
 * `diamondCut`) are told apart by how many of the namespaces each touches belong to the other recognized facets.
 */
export function matchFacets(facets: readonly LoupeFacet[], catalog: readonly CatalogFacet[]): FacetMatches {
  const matches: FacetMatches = { recognized: [], ambiguous: [], partial: [], own: [] };
  const served = facets.map(facet => selectorSet(facet.functionSelectors));
  const exact = served.map(selectors => catalog.filter(candidate => sameSet(selectors, catalogSelectors(candidate))));
  const owned = new Set(exact.filter(candidates => candidates.length === 1).map(([only]) => only.storage?.id));
  const touchesOwned = (candidate: CatalogFacet) => candidate.touches.filter(namespace => owned.has(namespace)).length;

  facets.forEach((facet, index) => {
    const candidates = exact[index];
    if (candidates.length > 0) {
      const [best, ...rest] = [...candidates].sort((a, b) => touchesOwned(b) - touchesOwned(a));
      const tied = rest.length > 0 && touchesOwned(rest[0]) === touchesOwned(best);
      if (tied) matches.ambiguous.push({ facet, candidates });
      else matches.recognized.push({ facet, catalog: best, alsoMatches: rest.map(candidate => candidate.name) });
      return;
    }
    const closest = catalog
      .map(candidate => ({ candidate, shared: sharedCount(served[index], catalogSelectors(candidate)) }))
      .filter(({ shared }) => shared > 0)
      .sort((a, b) => b.shared - a.shared || a.candidate.selectors.length - b.candidate.selectors.length)[0];
    if (closest) matches.partial.push({ facet, closest: closest.candidate, shared: closest.shared });
    else matches.own.push(facet);
  });

  return matches;
}
