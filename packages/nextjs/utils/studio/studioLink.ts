/** Lattice Studio's Hedera build, which knows the Hedera facets. */
export const STUDIO_URL = "https://lattice-studio-git-feat-hedera-david-dadas-projects.vercel.app/";

function base64url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * The "Open in Lattice Studio" link for a recipe, encoded as `scripts-js/studioLink.js` does: `#s=1.` followed by
 * the recipe JSON (minus `$schema`), raw-deflated and base64url-encoded. Nothing is uploaded; the fragment never
 * leaves the browser. The browser's deflate picks its own level, so the bytes can differ from Node's while the
 * recipe they carry is the same.
 */
export async function studioLink(recipe: { $schema?: string; [key: string]: unknown }) {
  const shared = { ...recipe };
  delete shared.$schema;
  const packed = new Blob([JSON.stringify(shared)]).stream().pipeThrough(new CompressionStream("deflate-raw"));
  return `${STUDIO_URL}#s=1.${base64url(new Uint8Array(await new Response(packed).arrayBuffer()))}`;
}
