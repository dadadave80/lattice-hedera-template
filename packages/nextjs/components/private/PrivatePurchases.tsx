"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Address, getAbiItem, toFunctionSelector, zeroAddress } from "viem";
import { useAccount, useSignMessage } from "wagmi";
import { DiamondNotDeployed } from "~~/components/diamond/DiamondNotDeployed";
import { BuyPrivatelyCard } from "~~/components/private/BuyPrivatelyCard";
import { InboxCard } from "~~/components/private/InboxCard";
import { ReceiveCard } from "~~/components/private/ReceiveCard";
import { useDeployedContractInfo, useScaffoldReadContract } from "~~/hooks/scaffold-hbar";
import { getParsedError, notification } from "~~/utils/scaffold-hbar";
import { stealthBuyAbi } from "~~/utils/stealth/abi";
import { STEALTH_KEYS_MESSAGE, StealthKeys, deriveStealthKeys } from "~~/utils/stealth/stealthAddress";

const BUY_FOR_SELECTOR = toFunctionSelector(getAbiItem({ abi: stealthBuyAbi, name: "buyFor" }));

export type KeysProps = { keys?: StealthKeys; onSign: () => void; isSigning: boolean };

/**
 * The private-purchase cards. The keys exist only in this component's state: they are gone when the page closes or the
 * wallet changes, and signing again derives the same ones.
 */
export const PrivatePurchases = () => {
  const { address } = useAccount();
  const { data: diamond, isLoading: isDiamondLoading } = useDeployedContractInfo({ contractName: "Diamond" });
  const {
    data: buyForFacet,
    isLoading: isLoupeLoading,
    isError: isLoupeError,
  } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "facetAddress",
    args: [BUY_FOR_SELECTOR],
  });
  const { signMessageAsync, isPending: isSigning } = useSignMessage();
  const [signed, setSigned] = useState<{ owner: Address; keys: StealthKeys }>();

  useEffect(() => setSigned(undefined), [address]);

  const sign = async () => {
    if (!address) return;
    try {
      const signature = await signMessageAsync({ message: STEALTH_KEYS_MESSAGE });
      setSigned({ owner: address, keys: deriveStealthKeys(signature) });
    } catch (error) {
      notification.error(getParsedError(error));
    }
  };

  if (isDiamondLoading || isLoupeLoading) {
    return <div className="h-64 rounded-2xl bg-base-200 animate-pulse" aria-hidden />;
  }

  if (!diamond) return <DiamondNotDeployed />;

  if (isLoupeError) {
    return (
      <div role="alert" className="alert alert-error">
        <span>
          The diamond&apos;s loupe did not answer, so this page cannot tell whether it sells privately. Reload.
        </span>
      </div>
    );
  }

  if (!buyForFacet || buyForFacet === zeroAddress) {
    return (
      <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300 text-center">
        <h2 className="font-bold text-xl m-0">This diamond does not sell privately yet</h2>
        <p className="text-base-content/70 m-0 mt-2">
          No facet serves <code>buyFor</code>. Its admin can add <code>StealthBuy</code>, <code>ERC6538Registry</code>{" "}
          and <code>ERC5564Announcer</code> with their initializers in one cut:
        </p>
        <pre className="text-left text-sm bg-base-200 rounded-xl p-4 mt-4 overflow-x-auto">
          yarn foundry:deploy --file DeployStealthBuy.s.sol --network hedera_testnet
        </pre>
        <p className="text-base-content/70 m-0 mt-4">
          The sale itself is on the{" "}
          <Link href="/sale" className="link">
            Sale page
          </Link>
          .
        </p>
      </div>
    );
  }

  const keys = signed?.owner === address ? signed?.keys : undefined;

  return (
    <>
      <ReceiveCard keys={keys} onSign={sign} isSigning={isSigning} />
      <BuyPrivatelyCard />
      <InboxCard keys={keys} onSign={sign} isSigning={isSigning} />
    </>
  );
};
