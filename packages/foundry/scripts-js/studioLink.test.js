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

// The same recipe encoded by Lattice Studio's own share-link encoder (lattice-studio@73e0403, feat/hedera).
const STUDIO_ENCODED =
  "https://lattice-studio-git-feat-hedera-david-dadas-projects.vercel.app/#s=1.lVDBbsIwDP0VFO3YSRTaqO0NdZuYtBNMuyAOTuLQiDapmsBAqP8-Z52ExG2nvBf7Pfv5xiQEaN2BVTfWgG9YxeaXstBc4ELpYq5QQiG54FJxBaLUiFIv9XyhykUmymypYZlnOU-1ELzgeclVmrGEBSBLpvD8zGWhRJazMWF4ke1JIat2-4RpkBg8YVY3YGxr7HGloA84kHz9ub2TlZTofe1sGFz7YqBzVtWnQJXXDocDWnndBtc_dhLfoERzRkJ_sg936vEtTo7qTZ3yfGK0kLEmxDMcjVW0uw_Ye-qa3mp3YzAcCNCrOmMjeBpQ_6bsW3elVUfK6HuU9PeY6T2aj8n_TO5XmOR7Klno6IBsjQoHmKkp1kyAjyndt8Uh2kcP2WAHX8SNo0Hp-AM";

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
