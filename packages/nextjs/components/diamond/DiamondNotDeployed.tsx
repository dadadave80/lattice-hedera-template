"use client";

import { useTargetNetwork } from "~~/hooks/scaffold-hbar";

/** Shown instead of a page's content when the wallet is on a network this project has no diamond on. */
export const DiamondNotDeployed = () => {
  const { targetNetwork } = useTargetNetwork();

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300 text-center">
      <h2 className="font-bold text-xl m-0">No diamond on {targetNetwork.name}</h2>
      <p className="text-base-content/70 m-0 mt-2">
        Switch your wallet to Hedera Testnet, or deploy your own with{" "}
        <code className="bg-base-200 px-1.5 py-0.5 rounded">yarn foundry:deploy --network hedera_testnet</code>.
      </p>
    </div>
  );
};
