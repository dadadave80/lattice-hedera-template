import { buildRecipe } from "./buildRecipe";
import { Catalog, CatalogFacet } from "./catalog";
import reference from "./fixtures/referenceDiamond.json";
import { matchFacets } from "./matchFacets";
import { describe, expect, it } from "vitest";
import { LoupeFacet } from "~~/utils/diamond/planCut";

const facet = (name: string): CatalogFacet => ({
  name,
  summary: "",
  selectors: [],
  touches: [],
  release: { address: "0x0000000000000000000000000000000000000001", version: "0.2.0" },
});

const catalog: Catalog = {
  tag: "dev-6c8db45",
  hash: "0x98f6be2df80deca8c6b6cd6dab9feecf3f02d924b943fa354561fbb686596d14",
  facets: [
    "ChainlinkAdapter",
    "HTSAdapter",
    "AccessControlDiamondCut",
    "EmergencyStop",
    "AccessControl",
    "Receive",
  ].map(facet),
};

describe("buildRecipe", () => {
  it("pins the catalog by tag and hash and runs no init", () => {
    expect(buildRecipe(catalog, ["Receive"], "Live diamond")).toEqual({
      schemaVersion: 1,
      name: "Live diamond",
      catalog: {
        tag: "dev-6c8db45",
        hash: "0x98f6be2df80deca8c6b6cd6dab9feecf3f02d924b943fa354561fbb686596d14",
      },
      facets: ["Receive"],
      owners: {},
      exclude: [],
      init: { kind: "none" },
    });
  });

  it("lists the facets in catalog order, as Studio exports them", () => {
    const recipe = buildRecipe(catalog, ["Receive", "AccessControl", "HTSAdapter", "ChainlinkAdapter"], "Live diamond");

    expect(recipe.facets).toEqual(["ChainlinkAdapter", "HTSAdapter", "AccessControl", "Receive"]);
  });

  it("leaves out a name the catalog does not have", () => {
    expect(buildRecipe(catalog, ["TokenSale", "Receive"], "Live diamond").facets).toEqual(["Receive"]);
  });

  // `studioRecipe` is what Studio's own exportRecipeJson (lattice-studio feat/hedera) writes for these facets.
  it("builds, for the reference diamond on Hedera testnet, the recipe Studio itself exports", () => {
    const catalog = reference.catalog as Catalog;
    const { recognized } = matchFacets(reference.loupe as LoupeFacet[], catalog.facets);
    const recipe = buildRecipe(
      catalog,
      recognized.map(match => match.catalog.name),
      reference.studioRecipe.name,
    );

    expect({ $schema: reference.studioRecipe.$schema, ...recipe }).toEqual(reference.studioRecipe);
  });
});
