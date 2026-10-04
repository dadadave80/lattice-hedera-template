"use client";

import { Address, Hex } from "viem";
import { DiamondNotDeployed } from "~~/components/diamond/DiamondNotDeployed";
import { HederaAddress } from "~~/components/scaffold-hbar";
import { useDeployedContractInfo, useScaffoldReadContract, useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { useSelectorNames } from "~~/hooks/useSelectorNames";

type Facet = { facetAddress: string; functionSelectors: readonly Hex[] };

/** The diamond as its loupe reports it: every facet address and the functions routed to it. */
export const FacetTable = () => {
  const { targetNetwork } = useTargetNetwork();
  const { data: diamond, isLoading } = useDeployedContractInfo({ contractName: "Diamond" });
  const { data } = useScaffoldReadContract({ contractName: "Diamond", functionName: "facets" });
  const facets = data as readonly Facet[] | undefined;
  const names = useSelectorNames();

  if (isLoading) return <div className="h-64 rounded-2xl bg-base-200 animate-pulse" aria-hidden />;
  if (!diamond) return <DiamondNotDeployed />;

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
      <div className="flex flex-wrap items-center justify-between gap-2 mb-4">
        <h2 className="font-bold text-xl m-0">Facets</h2>
        <HederaAddress address={diamond.address as Address} chain={targetNetwork} />
      </div>
      <div className="overflow-x-auto">
        <table className="table table-sm">
          <thead>
            <tr>
              <th>Facet</th>
              <th>Functions it serves</th>
            </tr>
          </thead>
          <tbody>
            {facets?.map(facet => (
              <tr key={facet.facetAddress}>
                <td className="align-top">
                  <HederaAddress address={facet.facetAddress as Address} chain={targetNetwork} />
                </td>
                <td>
                  <div className="flex flex-wrap gap-1">
                    {facet.functionSelectors.map(selector => (
                      <span key={selector} className="badge badge-ghost font-mono text-xs" title={selector}>
                        {names.get(selector) ?? selector}
                      </span>
                    ))}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="text-xs text-base-content/60 mt-4 mb-0">
        A selector shown as hex is served by the diamond but belongs to no contract in{" "}
        <code>contracts/deployedContracts.ts</code>. Deploying its facet with <code>yarn foundry:deploy</code> adds it.
      </p>
    </div>
  );
};
