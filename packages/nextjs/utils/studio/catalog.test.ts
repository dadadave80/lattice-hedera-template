import { CATALOG_URL, loadCatalog } from "./catalog";
import { describe, expect, it } from "vitest";

const HASH = "0x98f6be2df80deca8c6b6cd6dab9feecf3f02d924b943fa354561fbb686596d14";
const OTHER_HASH = "0x2ab42999bbfac307417b4265a7e9dbb8e004a8473bc9fc532b9bf33efa1d20c1";

const manifest = {
  default: "dev-6c8db45",
  catalogs: [
    { id: "dev-f4a32c8", tag: "dev-f4a32c8", hash: OTHER_HASH, path: "dev-f4a32c8/index.json" },
    { id: "dev-6c8db45", tag: "dev-6c8db45", hash: HASH, path: "dev-6c8db45/index.json" },
  ],
};

const receive = {
  name: "Receive",
  summary: "Bare-ETH acceptance as a facet.",
  selectors: [{ hex: "0x00000000", signature: "receive()" }],
  touches: [],
  release: { address: "0x7EC3278C4c8435D3351FEEe3A8CB081807c68F3E", version: "0.2.0" },
};

/** A `fetch` that serves `files` by URL and answers 404 to anything else. */
const serving = (files: Record<string, unknown>) => {
  const requested: string[] = [];
  const fetcher = async (url: string) => {
    requested.push(url);
    return url in files ? Response.json(files[url]) : new Response("Not Found", { status: 404 });
  };
  return { fetcher, requested };
};

describe("loadCatalog", () => {
  it("loads the catalog the manifest names as default, with the manifest's tag and hash", async () => {
    const { fetcher, requested } = serving({
      [`${CATALOG_URL}manifest.json`]: manifest,
      [`${CATALOG_URL}dev-6c8db45/index.json`]: { hash: HASH, facets: [receive] },
    });

    expect(await loadCatalog(fetcher)).toEqual({ tag: "dev-6c8db45", hash: HASH, facets: [receive] });
    expect(requested).toEqual([`${CATALOG_URL}manifest.json`, `${CATALOG_URL}dev-6c8db45/index.json`]);
  });

  it("refuses an index whose hash is not the one the manifest names", async () => {
    const { fetcher } = serving({
      [`${CATALOG_URL}manifest.json`]: manifest,
      [`${CATALOG_URL}dev-6c8db45/index.json`]: { hash: OTHER_HASH, facets: [receive] },
    });

    await expect(loadCatalog(fetcher)).rejects.toThrow("is not the catalog its manifest names");
  });

  it("fails when Studio does not serve a file", async () => {
    const { fetcher } = serving({ [`${CATALOG_URL}manifest.json`]: manifest });

    await expect(loadCatalog(fetcher)).rejects.toThrow("404");
  });

  it("reads the catalog from Studio's Hedera build", () => {
    expect(CATALOG_URL).toBe("https://lattice-studio-git-feat-hedera-david-dadas-projects.vercel.app/catalog/");
  });
});
