import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "fs";
import { inflateRawSync } from "zlib";
import { studioLink } from "./studioLink.js";

// The default recipe, frozen as a fixture so this test keeps passing after you customize yours.
const recipe = JSON.parse(
  readFileSync(
    new URL("../test/fixtures/default.recipe.json", import.meta.url),
    "utf8"
  )
);

// The same recipe encoded by Lattice Studio's own share-link encoder (lattice-studio@e909125, feat/hedera).
const STUDIO_ENCODED =
  "https://lattice-studio-git-feat-hedera-david-dadas-projects.vercel.app/#s=1.lVFBboMwEPxKZPVIpRDAAm4RbZVKPSVVL1EOxl6DFbCRbdJEEX_vUhpF5VCpp91ZzY5nx1fCmWeNqUh-JTVzNcnJ8pylkpawEjJdCuAs5bSkXFDBykwCcBnJ5Upkq7jM4kiyKIkTGsqypClNMirCmATEM5QkAk6PlKeijBMyBATOvOkFkHx_CIhkHLzDnhQ1U7pR-rgWrPNgcX3zvruD522RJDRea216zW8jmkTpFirlvL3gZM05OFcY7a1pnhRrjRZF70duC7YCzS87b7o5E_EWOKgTYPez9mb6Dl5Ge9NLIU0mhK6VVn7M6qi0wAOdh84ha6r5_kqYrbDBKlqlx-bBgvyOomvMBc0PGITrgONsfvjrKD4E_xO5RzVfv3Nmcf1J_BX1xDwgQbMWP45sQIBlCzEltSiZG4MznxrsTYnX0LIPxMqg93D4Ag";

const decode = (link) =>
  JSON.parse(
    inflateRawSync(Buffer.from(link.split("#s=1.")[1], "base64url")).toString()
  );

test("the link carries the recipe without its $schema", () => {
  const { $schema, ...expected } = recipe;

  assert.ok($schema);
  assert.deepEqual(decode(studioLink(recipe)), expected);
});

test("the link opens on Studio's Hedera build", () => {
  assert.ok(
    studioLink(recipe).startsWith(
      "https://lattice-studio-git-feat-hedera-david-dadas-projects.vercel.app/#s=1."
    )
  );
});

test("a link encoded by Studio itself decodes to the same recipe", () => {
  assert.deepEqual(decode(STUDIO_ENCODED), decode(studioLink(recipe)));
});
