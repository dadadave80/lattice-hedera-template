"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Address, Hex, createWalletClient, erc20Abi, http, isAddress, isAddressEqual } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { useAccount, useBalance, useReadContracts } from "wagmi";
import type { KeysProps } from "~~/components/private/PrivatePurchases";
import { HederaAddress } from "~~/components/scaffold-hbar";
import { useDeployedContractInfo, useTargetNetwork, useTransactor } from "~~/hooks/scaffold-hbar";
import scaffoldConfig, { ScaffoldConfig } from "~~/scaffold.config";
import { formatAmount } from "~~/utils/sale/units";
import { fetchAnnouncements, mirrorNodeUrl } from "~~/utils/stealth/announcements";
import {
  StealthKeys,
  checkAnnouncement,
  computeStealthPrivateKey,
  parseMetadata,
} from "~~/utils/stealth/stealthAddress";

type Delivery = { stealthAddress: Address; ephemeralPublicKey: Hex; token?: Address; timestamp: string };

/** Finds the deliveries made to the holder of the keys, and sweeps each one with its own stealth key. */
export const InboxCard = ({ keys, onSign, isSigning }: KeysProps) => {
  const { address } = useAccount();
  const { targetNetwork } = useTargetNetwork();
  const { data: diamond } = useDeployedContractInfo({ contractName: "Diamond" });

  const {
    data: announcements,
    isFetching,
    isError,
    refetch,
  } = useQuery({
    queryKey: ["stealthAnnouncements", targetNetwork.id, diamond?.address],
    queryFn: () => fetchAnnouncements(mirrorNodeUrl(targetNetwork.id), diamond?.address as Address),
    enabled: keys !== undefined && diamond !== undefined,
  });

  const deliveries = useMemo(() => {
    if (!keys || !announcements) return [];
    const mine = new Map<Address, Delivery>();
    for (const announcement of announcements) {
      const metadata = parseMetadata(announcement.metadata);
      if (!metadata || !checkAnnouncement({ ...announcement, viewTag: metadata.viewTag }, keys)) continue;
      mine.set(announcement.stealthAddress, { ...announcement, token: metadata.token });
    }
    return [...mine.values()].reverse();
  }, [announcements, keys]);

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="font-bold text-xl m-0">Inbox</h2>
        {keys && (
          <button className="btn btn-ghost btn-xs" onClick={() => refetch()} disabled={isFetching}>
            {isFetching && <span className="loading loading-spinner loading-xs" />}
            Refresh
          </button>
        )}
      </div>
      <p className="text-sm text-base-content/70 mt-1">
        Reads every announcement this diamond has made from the mirror node, and checks each one with your viewing key
        here in the browser.
      </p>

      {!address ? (
        <p className="text-sm m-0 mt-4">Connect the wallet that registered to see what was sent to it.</p>
      ) : !keys ? (
        <button className="btn btn-primary btn-sm mt-4" onClick={onSign} disabled={isSigning}>
          {isSigning && <span className="loading loading-spinner loading-xs" />}
          Sign to scan
        </button>
      ) : isError ? (
        <p className="text-sm text-error m-0 mt-4">The mirror node did not answer. Try Refresh.</p>
      ) : announcements === undefined ? (
        <div className="h-16 rounded-xl bg-base-200 animate-pulse mt-4" aria-hidden />
      ) : deliveries.length === 0 ? (
        <p className="text-sm m-0 mt-4">Nothing has been delivered to your meta-address yet.</p>
      ) : (
        <>
          <ul className="m-0 mt-4 p-0 list-none flex flex-col gap-4">
            {deliveries.map(delivery => (
              <DeliveryRow key={delivery.stealthAddress} delivery={delivery} keys={keys} />
            ))}
          </ul>
          <p className="text-xs text-base-content/60 mt-4 mb-0">
            Sweeping into the wallet that registered your meta-address links it to the delivery on chain. Sweep to an
            address nothing else ties to you to keep them apart.
          </p>
        </>
      )}
    </div>
  );
};

const DeliveryRow = ({ delivery, keys }: { delivery: Delivery; keys: StealthKeys }) => {
  const { address } = useAccount();
  const { targetNetwork } = useTargetNetwork();
  const [to, setTo] = useState("");
  const [isSweeping, setIsSweeping] = useState(false);

  // Signs locally with the stealth key: the connected wallet never sees it.
  const stealthClient = useMemo(
    () =>
      createWalletClient({
        account: privateKeyToAccount(computeStealthPrivateKey(delivery.ephemeralPublicKey, keys)),
        chain: targetNetwork,
        transport: http((scaffoldConfig.rpcOverrides as ScaffoldConfig["rpcOverrides"])?.[targetNetwork.id]),
      }),
    [delivery.ephemeralPublicKey, keys, targetNetwork],
  );
  const transactor = useTransactor(stealthClient);

  const token = delivery.token && ({ address: delivery.token, abi: erc20Abi, chainId: targetNetwork.id } as const);
  const { data: tokenData, refetch: refetchToken } = useReadContracts({
    contracts: token
      ? [
          { ...token, functionName: "symbol" },
          { ...token, functionName: "decimals" },
          { ...token, functionName: "balanceOf", args: [delivery.stealthAddress] },
        ]
      : [],
    query: { enabled: token !== undefined },
  });
  const [symbol, decimals, tokenBalance] = tokenData?.map(read => read.result) ?? [];
  const { data: hbarBalance, refetch: refetchHbar } = useBalance({
    address: delivery.stealthAddress,
    chainId: targetNetwork.id,
  });

  const isToRegisteringWallet = address !== undefined && isAddress(to) && isAddressEqual(to, address);
  const canSweep =
    delivery.token !== undefined &&
    isAddress(to) &&
    typeof tokenBalance === "bigint" &&
    tokenBalance > 0n &&
    hbarBalance !== undefined &&
    hbarBalance.value > 0n;

  const sweep = async () => {
    if (!delivery.token || !isAddress(to) || typeof tokenBalance !== "bigint") return;
    const tokenAddress = delivery.token;
    try {
      setIsSweeping(true);
      await transactor(() =>
        stealthClient.writeContract({
          address: tokenAddress,
          abi: erc20Abi,
          functionName: "transfer",
          args: [to, tokenBalance],
        }),
      );
      setTo("");
      await Promise.all([refetchToken(), refetchHbar()]);
    } catch {
      // The transactor has already shown the error.
    } finally {
      setIsSweeping(false);
    }
  };

  return (
    <li className="border border-base-300 rounded-xl p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <HederaAddress address={delivery.stealthAddress} chain={targetNetwork} />
        <span className="text-xs text-base-content/60">
          {new Date(Number(delivery.timestamp) * 1000).toLocaleString()}
        </span>
      </div>
      <p className="text-sm m-0 mt-2">
        {typeof tokenBalance === "bigint" && typeof decimals === "number"
          ? `${formatAmount(tokenBalance, decimals)} ${symbol ?? ""} · `
          : ""}
        {hbarBalance ? `${formatAmount(hbarBalance.value, hbarBalance.decimals)} HBAR` : "…"}
      </p>
      {delivery.token && (
        <div className="flex flex-wrap gap-3 mt-3">
          <input
            className="input input-bordered input-sm grow font-mono text-sm"
            placeholder="0x… sweep the tokens to"
            value={to}
            onChange={event => setTo(event.target.value.trim())}
          />
          <button className="btn btn-secondary btn-sm" onClick={sweep} disabled={!canSweep || isSweeping}>
            {isSweeping && <span className="loading loading-spinner loading-xs" />}
            Sweep
          </button>
        </div>
      )}
      {isToRegisteringWallet && (
        <div role="alert" className="alert alert-warning text-sm mt-3">
          <span>
            This is the wallet that registered your meta-address. Sweeping here shows on chain that this delivery was
            for it.
          </span>
        </div>
      )}
    </li>
  );
};
