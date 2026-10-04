"use client";

import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import { HederaAddress } from "~~/components/scaffold-hbar";
import { useDeployedContractInfo, useScaffoldReadContract, useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { useSelectorNames } from "~~/hooks/useSelectorNames";
import { LoupeFacet, knownContractName } from "~~/utils/diamond/planCut";
import { GenericContract, contracts } from "~~/utils/scaffold-hbar/contract";
import { buildRecipe } from "~~/utils/studio/buildRecipe";
import { loadCatalog } from "~~/utils/studio/catalog";
import { matchFacets } from "~~/utils/studio/matchFacets";
import { studioLink } from "~~/utils/studio/studioLink";

/** The diamond's facets as Lattice Studio's catalog names them, and a link that opens the Lattice ones in Studio. */
export const StudioCard = () => {
  const { targetNetwork } = useTargetNetwork();
  const publicClient = usePublicClient({ chainId: targetNetwork.id });
  const { data: diamond } = useDeployedContractInfo({ contractName: "Diamond" });
  const { data } = useScaffoldReadContract({ contractName: "Diamond", functionName: "facets" });
  const facets = data as readonly LoupeFacet[] | undefined;
  const names = useSelectorNames();
  const deployed = contracts?.[targetNetwork.id] as Record<string, GenericContract> | undefined;

  const catalog = useQuery({ queryKey: ["latticeStudioCatalog"], queryFn: () => loadCatalog(), staleTime: Infinity });
  const matches = useMemo(
    () => (facets && catalog.data ? matchFacets(facets, catalog.data.facets) : undefined),
    [facets, catalog.data],
  );
  const recipe = useMemo(
    () =>
      matches && catalog.data && diamond
        ? buildRecipe(
            catalog.data,
            matches.recognized.map(match => match.catalog.name),
            `Diamond ${diamond.address} on ${targetNetwork.name}`,
          )
        : undefined,
    [matches, catalog.data, diamond, targetNetwork.name],
  );
  const { data: link } = useQuery({
    queryKey: ["latticeStudioLink", recipe],
    queryFn: () => studioLink(recipe!),
    enabled: recipe !== undefined && recipe.facets.length > 0,
  });

  const releases = matches?.recognized.map(match => match.catalog.release.address) ?? [];
  const { data: releaseHasCode } = useQuery({
    queryKey: ["latticeReleasesWithCode", targetNetwork.id, releases],
    queryFn: async () => {
      const codes = await Promise.all(releases.map(address => publicClient!.getCode({ address })));
      return Object.fromEntries(releases.map((address, index) => [address, codes[index] !== undefined]));
    },
    enabled: publicClient !== undefined && releases.length > 0,
  });

  if (!diamond) return null;

  const facetRow = (facet: LoupeFacet, note?: string) => {
    const known = knownContractName(facet.facetAddress, deployed);
    return (
      <li key={facet.facetAddress} className="flex flex-col gap-1">
        <div className="flex flex-wrap items-center gap-2">
          {known && <span className="font-semibold">{known}</span>}
          <HederaAddress address={facet.facetAddress} chain={targetNetwork} />
        </div>
        <div className="flex flex-wrap gap-1">
          {facet.functionSelectors.map(selector => (
            <span key={selector} className="badge badge-ghost font-mono text-xs" title={selector}>
              {names.get(selector) ?? selector}
            </span>
          ))}
        </div>
        {note && <p className="text-xs text-base-content/60 m-0">{note}</p>}
      </li>
    );
  };

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <h2 className="font-bold text-xl m-0">Lattice Studio</h2>
          {catalog.data && (
            <span className="badge badge-ghost font-mono text-xs" title="The catalog the facets are named from">
              {catalog.data.tag}
            </span>
          )}
        </div>
        <a
          className={`btn btn-primary btn-sm ${link ? "" : "btn-disabled"}`}
          href={link}
          target="_blank"
          rel="noopener noreferrer"
          aria-disabled={!link}
        >
          Open in Lattice Studio
        </a>
      </div>
      <p className="text-sm text-base-content/70 mt-1">
        Each facet is named from Studio&apos;s catalog by the selectors it serves. The link opens the Lattice facets in
        Studio as a recipe, carried in the link&apos;s fragment and never uploaded. Studio shows the facets, not the
        live diamond&apos;s init history: the recipe runs no init, so Studio flags each facet that takes one, even
        though the diamond ran its inits when it was created.
      </p>

      {catalog.error && (
        <div role="alert" className="alert alert-warning text-sm mt-4">
          <span>Could not read Lattice Studio&apos;s catalog. {catalog.error.message}</span>
        </div>
      )}
      {!catalog.error && !matches && <div className="h-40 rounded-xl bg-base-200 animate-pulse mt-4" aria-hidden />}

      {matches && (
        <>
          <div className="overflow-x-auto mt-4">
            <table className="table table-sm">
              <thead>
                <tr>
                  <th>Lattice facet</th>
                  <th>Storage</th>
                  <th>Lattice&apos;s release on {targetNetwork.name}</th>
                </tr>
              </thead>
              <tbody>
                {matches.recognized.map(({ facet, catalog: entry, alsoMatches }) => (
                  <tr key={facet.facetAddress}>
                    <td className="align-top">
                      <div className="font-semibold">{entry.name}</div>
                      <div className="text-xs text-base-content/70">{entry.summary}</div>
                      {alsoMatches.length > 0 && (
                        <div className="text-xs text-base-content/60 mt-1">
                          Its selectors also match {alsoMatches.join(", ")}. The diamond&apos;s other facets own the
                          storage {entry.name} works on, so the recipe names {entry.name}.
                        </div>
                      )}
                    </td>
                    <td className="align-top font-mono text-xs">{entry.storage?.id ?? "none, stateless"}</td>
                    <td className="align-top">
                      {releaseHasCode === undefined ? (
                        <span className="loading loading-dots loading-xs" aria-label="Checking" />
                      ) : releaseHasCode[entry.release.address] ? (
                        <div className="flex flex-col gap-1">
                          <span className="badge badge-success badge-sm">Deployed</span>
                          <HederaAddress address={entry.release.address} chain={targetNetwork} />
                        </div>
                      ) : (
                        <span className="badge badge-ghost badge-sm" title={entry.release.address}>
                          Not deployed
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="text-xs text-base-content/60 mt-2 mb-0">
            The release column checks whether Lattice&apos;s own deployment of each facet, at the address Studio&apos;s
            catalog gives, has code here. This project compiled the diamond&apos;s facets itself, so they live at their
            own addresses; the column says only whether the release exists on this network.
          </p>

          {matches.ambiguous.length + matches.partial.length > 0 && (
            <div className="mt-6">
              <h3 className="font-semibold text-base m-0">Not exactly a catalog facet</h3>
              <p className="text-xs text-base-content/60 mt-1">The recipe leaves these out.</p>
              <ul className="text-sm m-0 mt-2 p-0 list-none flex flex-col gap-3">
                {matches.ambiguous.map(({ facet, candidates }) =>
                  facetRow(
                    facet,
                    `Serves exactly the selectors of ${candidates.map(candidate => candidate.name).join(" and of ")}, and nothing tells them apart.`,
                  ),
                )}
                {matches.partial.map(({ facet, closest, shared }) =>
                  facetRow(
                    facet,
                    `Serves ${shared} of ${closest.name}'s ${closest.selectors.length} selectors, and ${facet.functionSelectors.length} in all.`,
                  ),
                )}
              </ul>
            </div>
          )}

          {matches.own.length > 0 && (
            <div className="mt-6">
              <h3 className="font-semibold text-base m-0">This template&apos;s own</h3>
              <p className="text-xs text-base-content/60 mt-1">
                Studio&apos;s catalog has no facet with any of these selectors, so the recipe leaves them out.
              </p>
              <ul className="text-sm m-0 mt-2 p-0 list-none flex flex-col gap-3">
                {matches.own.map(facet => facetRow(facet))}
              </ul>
            </div>
          )}
        </>
      )}
    </div>
  );
};
