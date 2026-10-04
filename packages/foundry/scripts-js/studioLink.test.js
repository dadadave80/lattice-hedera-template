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

// The same recipe encoded by Lattice Studio's own share-link encoder (lattice-studio@9c9d9eb).
const STUDIO_ENCODED =
  "https://lattice-studio-topaz.vercel.app/#s=1.XU_JbsIwEP0VNOqRStkgJDeUtmqlnqjUC-IwtifEIrEj21AQyr933PTEad5sb7mDxIC9PUJ9hw59BzUk1wxFkVVVJUSLMk_KIi15sF5hSZUSYkNJUuCmKHMhq1au8kxUos1zajFVWSJTWEJApgRFl-e2wDyTG5iWQFfZnxVBvT8sgakpeMbQdKhNr81pq3AM5Ph9KyV531gTnO1fNA7WqOYcePM6kDuSkbevYMfHS-53JElfiNH_26c9j_QWxeL3rknXq7ljD9roEJOftFFs1wcaPV_Ntd7fAd2RAVc1aBPBk6P2L9jY2xtbnTiWH0ny7DHGRySfDnxgcODQ8E6KHC7U7Gsh0Eeb9seQiyKRSXY04Df32rJcOv0C";

const decode = (link) =>
  JSON.parse(
    inflateRawSync(Buffer.from(link.split("#s=1.")[1], "base64url")).toString()
  );

test("the link carries the recipe without its $schema", () => {
  const { $schema, ...expected } = recipe;

  assert.ok($schema);
  assert.deepEqual(decode(studioLink(recipe)), expected);
});

test("the link opens on the hosted Studio", () => {
  assert.ok(
    studioLink(recipe).startsWith(
      "https://lattice-studio-topaz.vercel.app/#s=1."
    )
  );
});

test("a link encoded by Studio itself decodes to the same recipe", () => {
  assert.deepEqual(decode(STUDIO_ENCODED), decode(studioLink(recipe)));
});
