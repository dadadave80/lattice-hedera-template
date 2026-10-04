import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath, pathToFileURL } from "url";
import { deflateRawSync } from "zlib";

const STUDIO_URL = "https://lattice-studio-topaz.vercel.app/";

/**
 * The "Open in Lattice Studio" link for a recipe. Studio reads a recipe from the URL fragment:
 * `#s=1.` followed by the recipe JSON (minus `$schema`), raw-deflated and base64url-encoded.
 * Nothing is uploaded; the fragment never leaves the browser.
 */
export function studioLink(recipe) {
  const { $schema, ...shared } = recipe;
  const packed = deflateRawSync(Buffer.from(JSON.stringify(shared)), {
    level: 9,
  });
  return `${STUDIO_URL}#s=1.${packed.toString("base64url")}`;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const recipePath = join(
    dirname(fileURLToPath(import.meta.url)),
    "..",
    "diamond.recipe.json"
  );
  console.log(studioLink(JSON.parse(readFileSync(recipePath, "utf8"))));
}
