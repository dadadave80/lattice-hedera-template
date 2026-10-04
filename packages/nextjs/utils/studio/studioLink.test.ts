import recipe from "../../../foundry/test/fixtures/default.recipe.json";
import { STUDIO_URL, studioLink } from "./studioLink";
import { inflateRawSync } from "node:zlib";
import { describe, expect, it } from "vitest";

// The default recipe encoded by Lattice Studio's own share-link encoder, copied from scripts-js/studioLink.test.js.
const STUDIO_ENCODED =
  "https://lattice-studio-git-feat-hedera-david-dadas-projects.vercel.app/#s=1.lVDBbsIwDP0VFO3YSRTaqO0NdZuYtBNMuyAOTuLQiDapmsBAqP8-Z52ExG2nvBf7Pfv5xiQEaN2BVTfWgG9YxeaXstBc4ELpYq5QQiG54FJxBaLUiFIv9XyhykUmymypYZlnOU-1ELzgeclVmrGEBSBLpvD8zGWhRJazMWF4ke1JIat2-4RpkBg8YVY3YGxr7HGloA84kHz9ub2TlZTofe1sGFz7YqBzVtWnQJXXDocDWnndBtc_dhLfoERzRkJ_sg936vEtTo7qTZ3yfGK0kLEmxDMcjVW0uw_Ye-qa3mp3YzAcCNCrOmMjeBpQ_6bsW3elVUfK6HuU9PeY6T2aj8n_TO5XmOR7Klno6IBsjQoHmKkp1kyAjyndt8Uh2kcP2WAHX8SNo0Hp-AM";

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
