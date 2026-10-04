import recipe from "../../../foundry/test/fixtures/default.recipe.json";
import { STUDIO_URL, studioLink } from "./studioLink";
import { inflateRawSync } from "node:zlib";
import { describe, expect, it } from "vitest";

// The default recipe encoded by Lattice Studio's own share-link encoder, copied from scripts-js/studioLink.test.js.
const STUDIO_ENCODED =
  "https://lattice-studio-git-feat-hedera-david-dadas-projects.vercel.app/#s=1.lVFBboMwEPxKZPVIpRDAAm4RbZVKPSVVL1EOxl6DFbCRbdJEEX_vUhpF5VCpp91ZzY5nx1fCmWeNqUh-JTVzNcnJ8pylkpawEjJdCuAs5bSkXFDBykwCcBnJ5Upkq7jM4kiyKIkTGsqypClNMirCmATEM5QkAk6PlKeijBMyBATOvOkFkHx_CIhkHLzDnhQ1U7pR-rgWrPNgcX3zvruD522RJDRea216zW8jmkTpFirlvL3gZM05OFcY7a1pnhRrjRZF70duC7YCzS87b7o5E_EWOKgTYPez9mb6Dl5Ge9NLIU0mhK6VVn7M6qi0wAOdh84ha6r5_kqYrbDBKlqlx-bBgvyOomvMBc0PGITrgONsfvjrKD4E_xO5RzVfv3Nmcf1J_BX1xDwgQbMWP45sQIBlCzEltSiZG4MznxrsTYnX0LIPxMqg93D4Ag";

const decode = (link: string) =>
  JSON.parse(inflateRawSync(Buffer.from(link.split("#s=1.")[1], "base64url")).toString());

describe("studioLink", () => {
  it("carries the recipe without its $schema", async () => {
    const { $schema, ...expected } = recipe;

    expect($schema).toBeTruthy();
    expect(decode(await studioLink(recipe))).toEqual(expected);
  });

  it("opens on Studio's Hedera build", async () => {
    expect(STUDIO_URL).toBe("https://lattice-studio-git-feat-hedera-david-dadas-projects.vercel.app/");
    expect((await studioLink(recipe)).startsWith(`${STUDIO_URL}#s=1.`)).toBe(true);
  });

  it("decodes to the same recipe as a link encoded by Studio itself", async () => {
    expect(decode(await studioLink(recipe))).toEqual(decode(STUDIO_ENCODED));
  });

  it("writes base64url without padding, as Node's encoder and Studio's do", async () => {
    expect(await studioLink(recipe)).toMatch(/#s=1\.[A-Za-z0-9_-]+$/);
  });
});
