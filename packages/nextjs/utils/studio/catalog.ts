import { STUDIO_URL } from "./studioLink";
import { Address, Hex } from "viem";

/** Where Studio's Hedera build serves its catalogs. Studio answers with CORS `*`, so the app reads them directly. */
export const CATALOG_URL = `${STUDIO_URL}catalog/`;

/** What the app reads of one facet in Studio's catalog. */
export type CatalogFacet = {
  name: string;
  summary: string;
  selectors: { hex: Hex; signature: string }[];
  /** The ERC-7201 namespace the facet's library owns. A facet without one is stateless. */
  storage?: { id: string; slot: Hex };
  /** Namespaces the facet reads or writes that other facets own. */
  touches: string[];
  /** Where Lattice's deterministic deployment of the facet lives, on every chain it has reached. */
  release: { address: Address; version: string };
};

/** One of Studio's catalogs: the tag and hash a recipe pins, and the facets it offers. */
export type Catalog = { tag: string; hash: Hex; facets: CatalogFacet[] };

type Manifest = { default: string; catalogs: { id: string; tag: string; hash: Hex; path: string }[] };

async function fetchJson<T>(fetcher: (url: string) => Promise<Response>, url: string): Promise<T> {
  const response = await fetcher(url);
  if (!response.ok) throw new Error(`Lattice Studio answered ${response.status} for ${url}`);
  return response.json();
}

/** Studio's default catalog: its manifest names it, and its index lists the facets. */
export async function loadCatalog(fetcher: (url: string) => Promise<Response> = fetch): Promise<Catalog> {
  const manifest = await fetchJson<Manifest>(fetcher, `${CATALOG_URL}manifest.json`);
  const entry = manifest.catalogs.find(catalog => catalog.id === manifest.default);
  if (!entry) throw new Error(`Lattice Studio's manifest names ${manifest.default} as default but does not list it`);
  const index = await fetchJson<{ hash: Hex; facets: CatalogFacet[] }>(fetcher, `${CATALOG_URL}${entry.path}`);
  if (index.hash !== entry.hash) throw new Error(`${entry.path} is not the catalog its manifest names`);
  return { tag: entry.tag, hash: entry.hash, facets: index.facets };
}
