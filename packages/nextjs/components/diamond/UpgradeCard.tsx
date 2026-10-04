"use client";

import { useState } from "react";
import { Address, isAddress, parseAbi, zeroAddress } from "viem";
import { usePublicClient } from "wagmi";
import { useDeployedContractInfo, useScaffoldWriteContract, useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { useSelectorNames } from "~~/hooks/useSelectorNames";
import { FacetCut, FacetCutAction, planCut, unpackSelectors } from "~~/utils/diamond/planCut";
import { notification } from "~~/utils/scaffold-hbar";
import { GenericContract, contracts } from "~~/utils/scaffold-hbar/contract";

/** ERC-8153 on the facet, and the loupe on the diamond: all an upgrade needs to read. */
const upgradeAbi = parseAbi([
  "function exportSelectors() pure returns (bytes)",
  "function facetAddress(bytes4 selector) view returns (address)",
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
  const [cuts, setCuts] = useState<FacetCut[]>();

  const preview = async () => {
    if (!publicClient || !diamond || !isAddress(facet)) return;
    try {
      const packed = await publicClient.readContract({
        address: facet,
        abi: upgradeAbi,
        functionName: "exportSelectors",
      });
      const selectors = unpackSelectors(packed);
      const routes = await Promise.all(
        selectors.map(selector =>
          publicClient.readContract({
            address: diamond.address as Address,
            abi: upgradeAbi,
            functionName: "facetAddress",
            args: [selector],
          }),
        ),
      );
      setCuts(planCut(facet, selectors, routes));
    } catch {
      setCuts(undefined);
      notification.error("That address does not answer exportSelectors(). Is it a deployed Lattice facet?");
    }
  };

  const cut = async () => {
    if (!cuts) return;
    await writeContractAsync({ functionName: "diamondCut", args: [cuts, zeroAddress, "0x"] });
    setCuts(undefined);
  };

  if (!diamond) return null;

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
            setCuts(undefined);
          }}
        />
        <button className="btn btn-secondary btn-sm" onClick={preview} disabled={!isAddress(facet)}>
          Preview cut
        </button>
      </div>

      {cuts && cuts.length === 0 && <p className="text-sm mt-4 mb-0">This facet is already mounted. Nothing to cut.</p>}

      {cuts && cuts.length > 0 && (
        <div className="mt-4">
          <ul className="text-sm m-0 p-0 list-none flex flex-col gap-2">
            {cuts.map(planned => (
              <li key={planned.action}>
                <span className="font-semibold">{ACTION_LABELS[planned.action]}</span>{" "}
                <span className="font-mono text-xs">
                  {planned.functionSelectors.map(selector => names.get(selector) ?? selector).join(", ")}
                </span>
              </li>
            ))}
          </ul>
          <button className="btn btn-primary btn-sm mt-4" onClick={cut} disabled={isMining}>
            Cut into the diamond
          </button>
        </div>
      )}
    </div>
  );
};
