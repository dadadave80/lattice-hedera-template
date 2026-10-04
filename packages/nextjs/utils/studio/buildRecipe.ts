import { Catalog } from "./catalog";
import { Hex } from "viem";

/** A Lattice Studio recipe (`schemaVersion` 1), as `diamond.recipe.json` holds one. */
export type Recipe = {
  schemaVersion: 1;
  name: string;
  catalog: { tag: string; hash: Hex };
  facets: string[];
  owners: Record<Hex, string>;
  exclude: Hex[];
  init: { kind: "none" };
};

/**
 * A recipe that composes `facetNames` from `catalog` with no init. Studio exports facets in catalog order, so the
 * recipe lists them that way whatever order they come in.
 */
export function buildRecipe(catalog: Catalog, facetNames: string[], name: string): Recipe {
  return {
    schemaVersion: 1,
    name,
    catalog: { tag: catalog.tag, hash: catalog.hash },
    facets: catalog.facets.map(facet => facet.name).filter(facet => facetNames.includes(facet)),
    owners: {},
    exclude: [],
    init: { kind: "none" },
  };
}
