"use client";

import { useState } from "react";
import { HederaPortalFaucet } from "@scaffold-hbar-ui/components";
import { zeroAddress } from "viem";
import { useAccount, useConfig, useReadContract, useWriteContract } from "wagmi";
import { CheckCircleIcon, DocumentDuplicateIcon } from "@heroicons/react/24/outline";
import type { KeysProps } from "~~/components/private/PrivatePurchases";
import { useCopyToClipboard, useDeployedContractInfo, useTargetNetwork, useTransactor } from "~~/hooks/scaffold-hbar";
import { useWatchedBalance } from "~~/hooks/useWatchedBalance";
import { AllowedChainIds } from "~~/utils/scaffold-hbar";
import { simulateContractWriteAndNotifyError } from "~~/utils/scaffold-hbar/contract";
import { erc6538RegistryAbi } from "~~/utils/stealth/abi";
import { SCHEME_ID, encodeMetaAddress } from "~~/utils/stealth/stealthAddress";

/** Derives the connected wallet's stealth keys and registers its meta-address, so others can pay it privately. */
export const ReceiveCard = ({ keys, onSign, isSigning }: KeysProps) => {
  const { address } = useAccount();
  const { targetNetwork } = useTargetNetwork();
  const { data: diamond } = useDeployedContractInfo({ contractName: "Diamond" });
  const metaAddress = keys && encodeMetaAddress(keys.spendingPublicKey, keys.viewingPublicKey);

  const { data: registered, refetch: refetchRegistered } = useReadContract({
    chainId: targetNetwork.id,
    address: diamond?.address,
    abi: erc6538RegistryAbi,
    functionName: "stealthMetaAddressOf",
    args: [address ?? zeroAddress, SCHEME_ID],
    query: { enabled: diamond !== undefined && address !== undefined },
  });
  const { data: walletBalance } = useWatchedBalance(address);
  // The relay cannot simulate a transaction from an address Hedera has no account for.
  const isUnfunded = walletBalance?.value === 0n;

  const wagmiConfig = useConfig();
  const transactor = useTransactor();
  const { writeContractAsync } = useWriteContract();
  const [isRegistering, setIsRegistering] = useState(false);
  const { copyToClipboard, isCopiedToClipboard } = useCopyToClipboard();

  const register = async () => {
    if (!diamond || !metaAddress) return;
    const request = {
      chainId: targetNetwork.id,
      address: diamond.address,
      abi: erc6538RegistryAbi,
      functionName: "registerKeys",
      args: [SCHEME_ID, metaAddress],
    } as const;
    try {
      setIsRegistering(true);
      await simulateContractWriteAndNotifyError({
        wagmiConfig,
        writeContractParams: request,
        chainId: targetNetwork.id as AllowedChainIds,
      });
      await transactor(() => writeContractAsync(request));
      await refetchRegistered();
    } catch {
      // The simulation or the transactor has already shown the error.
    } finally {
      setIsRegistering(false);
    }
  };

  const hasRegistration = registered !== undefined && registered !== "0x";
  const isRegistered = metaAddress !== undefined && registered?.toLowerCase() === metaAddress.toLowerCase();
  const hasOtherRegistration = metaAddress !== undefined && hasRegistration;

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
      <h2 className="font-bold text-xl m-0">Receive privately</h2>
      <p className="text-sm text-base-content/70 mt-1">
        Sign one message to derive a spending key and a viewing key from your wallet. They stay in this tab, and a
        standard wallet gives the same keys each time you sign. Register the meta-address built from them, and anyone
        can buy tokens for you without your address appearing in the purchase.
      </p>

      {!address ? (
        <p className="text-sm m-0 mt-4">Connect a wallet to receive privately.</p>
      ) : !keys ? (
        <>
          {hasRegistration && (
            <p className="text-sm m-0 mt-4">
              This wallet has registered a meta-address here. Sign to see it and your inbox.
            </p>
          )}
          <button className="btn btn-primary btn-sm mt-4" onClick={onSign} disabled={isSigning}>
            {isSigning && <span className="loading loading-spinner loading-xs" />}
            Sign to derive your keys
          </button>
        </>
      ) : (
        <div className="mt-4">
          <div className="flex items-center justify-between gap-2">
            <span className="text-sm font-medium">Your stealth meta-address</span>
            <button className="btn btn-ghost btn-xs" onClick={() => metaAddress && copyToClipboard(metaAddress)}>
              {isCopiedToClipboard ? (
                <CheckCircleIcon className="h-4 w-4" aria-hidden="true" />
              ) : (
                <DocumentDuplicateIcon className="h-4 w-4" aria-hidden="true" />
              )}
              {isCopiedToClipboard ? "Copied" : "Copy"}
            </button>
          </div>
          <p className="font-mono text-xs break-all bg-base-200 rounded-lg p-3 m-0 mt-1">{metaAddress}</p>
          <div className="flex flex-wrap items-center gap-3 mt-4">
            {isRegistered ? (
              <span className="badge badge-success">Registered on this diamond</span>
            ) : (
              <button className="btn btn-primary btn-sm" onClick={register} disabled={isRegistering || isUnfunded}>
                {isRegistering && <span className="loading loading-spinner loading-xs" />}
                Register
              </button>
            )}
          </div>
          {!isRegistered && hasOtherRegistration && (
            <p className="text-sm text-warning mt-4 mb-0">
              This wallet registered another meta-address. Registering replaces it. Deliveries already sent to the old
              one can only be found with the keys that made it. If this wallet registered from this page before, its
              signatures change each time, as some smart-contract and MPC wallets&apos; do, and it cannot keep stealth
              keys here.
            </p>
          )}
          {isUnfunded && (
            <p className="text-sm text-warning mt-4 mb-0">
              This wallet holds no HBAR, so it cannot pay for a transaction. Fund it first:{" "}
              <HederaPortalFaucet variant="link" label="Use the faucet" showIcon={false} />
            </p>
          )}
        </div>
      )}
    </div>
  );
};
