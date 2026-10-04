"use client";

import { useState } from "react";
import { Address, Hex, isAddress, parseAbi, zeroAddress } from "viem";
import { usePublicClient } from "wagmi";
import { HederaAddress } from "~~/components/scaffold-hbar";
import { useDeployedContractInfo, useScaffoldWriteContract, useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { useSelectorNames } from "~~/hooks/useSelectorNames";
import {
  FacetCut,
  FacetCutAction,
  LoupeFacet,
  knownContractName,
  outgoingFacets,
  planCut,
  selectorsOutsideSale,
  unpackSelectors,
} from "~~/utils/diamond/planCut";
import { notification } from "~~/utils/scaffold-hbar";
import { GenericContract, contracts } from "~~/utils/scaffold-hbar/contract";

/** ERC-8153 on the facet, and the loupe on the diamond: all an upgrade needs to read. */
const upgradeAbi = parseAbi([
  "function exportSelectors() pure returns (bytes)",
  "function facets() view returns ((address facetAddress, bytes4[] functionSelectors)[])",
]);

const ACTION_LABELS = { [FacetCutAction.Add]: "Add", [FacetCutAction.Replace]: "Replace" } as Record<number, string>;

/** Cuts one facet into the live diamond: reads what it exports, plans Add and Replace, and sends `diamondCut`. */
export const UpgradeCard = () => {
  const { targetNetwork } = useTargetNetwork();
  const publicClient = usePublicClient({ chainId: targetNetwork.id });
  const { data: diamond } = useDeployedContractInfo({ contractName: "Diamond" });
  const { writeContractAsync, isMining } = useScaffoldWriteContract({ contractName: "Diamond" });
  const names = useSelectorNames();

  // `yarn foundry:deploy --file DeployTokenSaleV2.s.sol` records the walkthrough's facet here.
  const deployed = contracts?.[targetNetwork.id] as Record<string, GenericContract> | undefined;
  const [facet, setFacet] = useState<string>(deployed?.TokenSaleV2?.address ?? "");
  const [plan, setPlan] = useState<{ facet: Address; cuts: FacetCut[]; facets: readonly LoupeFacet[] }>();

  const preview = async () => {
    if (!publicClient || !diamond || !isAddress(facet)) return;
    try {
      const [packed, loupe] = await Promise.all([
        publicClient.readContract({ address: facet, abi: upgradeAbi, functionName: "exportSelectors" }),
        publicClient.readContract({ address: diamond.address as Address, abi: upgradeAbi, functionName: "facets" }),
      ]);
      const selectors = unpackSelectors(packed);
      const routes = selectors.map(
        selector => loupe.find(row => row.functionSelectors.includes(selector))?.facetAddress ?? zeroAddress,
      );
      setPlan({ facet, cuts: planCut(facet, selectors, routes), facets: loupe });
    } catch {
      setPlan(undefined);
      notification.error("That address does not answer exportSelectors(). Is it a deployed Lattice facet?");
    }
  };

  const cut = async () => {
    if (!plan) return;
    await writeContractAsync({ functionName: "diamondCut", args: [plan.cuts, zeroAddress, "0x"] });
    setPlan(undefined);
  };

  if (!diamond) return null;

  const nameList = (selectors: readonly Hex[]) => selectors.map(selector => names.get(selector) ?? selector).join(", ");
  const known = plan && knownContractName(plan.facet, deployed);
  const outside = plan ? selectorsOutsideSale(plan.cuts, plan.facets) : [];

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
      <h2 className="font-bold text-xl m-0">Upgrade</h2>
      <p className="text-sm text-base-content/70 mt-1">
        Paste the address of a deployed facet. The diamond keeps its address and its storage; only the code behind the
        listed functions changes. Only the diamond&apos;s admin can send the cut.
      </p>

      <div className="flex flex-wrap gap-3 mt-4">
        <input
          className="input input-bordered grow font-mono text-sm"
          placeholder="0x… facet address"
          value={facet}
          onChange={event => {
            setFacet(event.target.value);
            setPlan(undefined);
          }}
        />
        <button className="btn btn-secondary btn-sm" onClick={preview} disabled={!isAddress(facet)}>
          Preview cut
        </button>
      </div>

      {plan && plan.cuts.length === 0 && (
        <p className="text-sm mt-4 mb-0">This facet is already mounted. Nothing to cut.</p>
      )}

      {plan && plan.cuts.length > 0 && (
        <div className="mt-4">
          {known ? (
            <p className="text-sm mt-0 mb-3">
              This address is <span className="font-semibold">{known}</span> in{" "}
              <code>contracts/deployedContracts.ts</code>.
            </p>
          ) : (
            <div role="alert" className="alert alert-warning text-sm mb-3">
              <span>
                This address is not in <code>contracts/deployedContracts.ts</code>, so it is not one of this
                project&apos;s deployments. A facet only reports its own selectors, so read its code before you cut it
                in.
              </span>
            </div>
          )}
          <ul className="text-sm m-0 p-0 list-none flex flex-col gap-2">
            {plan.cuts.map(planned => (
              <li key={planned.action}>
                <span className="font-semibold">{ACTION_LABELS[planned.action]}</span>{" "}
                {planned.action === FacetCutAction.Replace ? (
                  <ul className="m-0 mt-1 p-0 list-none flex flex-col gap-2">
                    {outgoingFacets([planned], plan.facets).map(from => (
                      <li key={from.facetAddress} className="flex flex-wrap items-center gap-2">
                        <span className="font-mono text-xs">{nameList(from.functionSelectors)}</span>
                        <span className="text-base-content/60">now served by</span>
                        <HederaAddress address={from.facetAddress} chain={targetNetwork} />
                      </li>
                    ))}
                  </ul>
                ) : (
                  <span className="font-mono text-xs">{nameList(planned.functionSelectors)}</span>
                )}
              </li>
            ))}
          </ul>
          {outside.length > 0 && (
            <div role="alert" className="alert alert-warning text-sm mt-4">
              <span>
                Outside the sale: <span className="font-mono text-xs">{nameList(outside)}</span>. These are not served
                by the sale&apos;s facet, or they control upgrades. A facet that takes them over can take over the
                diamond.
              </span>
            </div>
          )}
          <button className="btn btn-primary btn-sm mt-4" onClick={cut} disabled={isMining}>
            Cut into the diamond
          </button>
        </div>
      )}
    </div>
  );
};
