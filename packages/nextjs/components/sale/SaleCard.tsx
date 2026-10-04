"use client";

import { useState } from "react";
import { HbarInput, HederaPortalFaucet } from "@scaffold-hbar-ui/components";
import { erc20Abi, parseAbi, zeroAddress } from "viem";
import { useAccount, useReadContract, useReadContracts, useWriteContract } from "wagmi";
import { DiamondNotDeployed } from "~~/components/diamond/DiamondNotDeployed";
import {
  useDeployedContractInfo,
  useScaffoldReadContract,
  useScaffoldWriteContract,
  useTargetNetwork,
  useTransactor,
} from "~~/hooks/scaffold-hbar";
import { useSale } from "~~/hooks/useSale";
import { hrc719Abi } from "~~/utils/sale/hrc719";
import { TINYBAR_DECIMALS, formatAmount, hbarToTinybars, minTokensOut, tinybarsToWeibars } from "~~/utils/sale/units";

/** Accept up to 1% fewer tokens than quoted if the oracle moves before the transaction lands. */
const SLIPPAGE_BPS = 100n;

/** Only a diamond that has been upgraded to TokenSaleV2 answers this; see the README's upgrade walkthrough. */
const bonusAbi = parseAbi(["function bonusBps() pure returns (uint256)"]);

export const SaleCard = () => {
  const { address } = useAccount();
  const { targetNetwork } = useTargetNetwork();
  const sale = useSale();
  const { data: diamond, isLoading: isDiamondLoading } = useDeployedContractInfo({ contractName: "Diamond" });
  const [hbar, setHbar] = useState("");
  const [isAssociating, setIsAssociating] = useState(false);
  const tinybars = hbarToTinybars(hbar);

  const { data: hbarUsd } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "latestAnswer",
    args: [sale.feedKey],
    query: { enabled: sale.isLaunched },
  });
  const { data: quote } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "quote",
    args: [tinybars],
    query: { enabled: sale.isLaunched && tinybars !== undefined },
  });

  // An HTS token answers the ERC-20 read functions at its own address.
  const token = { address: sale.token, abi: erc20Abi } as const;
  const { data: tokenData, refetch: refetchToken } = useReadContracts({
    contracts: [
      { ...token, functionName: "name" },
      { ...token, functionName: "symbol" },
      { ...token, functionName: "balanceOf", args: [diamond?.address ?? zeroAddress] },
      { ...token, functionName: "balanceOf", args: [address ?? zeroAddress] },
    ],
    query: { enabled: sale.isLaunched && diamond !== undefined },
  });
  const [name, symbol, available, owned] = tokenData?.map(read => read.result) ?? [];

  const { data: isAssociated, refetch: refetchAssociation } = useReadContract({
    address: sale.token,
    abi: hrc719Abi,
    functionName: "isAssociated",
    account: address,
    query: { enabled: sale.isLaunched && address !== undefined },
  });

  const { data: bonusBps } = useReadContract({
    address: diamond?.address,
    abi: bonusAbi,
    functionName: "bonusBps",
    query: { enabled: diamond !== undefined, retry: false },
  });

  const transactor = useTransactor();
  const { writeContractAsync: writeToken } = useWriteContract();
  const { writeContractAsync: writeDiamond, isMining: isBuying } = useScaffoldWriteContract({
    contractName: "Diamond",
  });

  const associate = async () => {
    if (!sale.token) return;
    const tokenAddress = sale.token;
    try {
      setIsAssociating(true);
      await transactor(() =>
        writeToken({ address: tokenAddress, abi: hrc719Abi, functionName: "associate", chainId: targetNetwork.id }),
      );
      await refetchAssociation();
    } finally {
      setIsAssociating(false);
    }
  };

  const buy = async () => {
    if (tinybars === undefined || quote === undefined) return;
    await writeDiamond({
      functionName: "buy",
      args: [minTokensOut(quote, SLIPPAGE_BPS)],
      // The contract sees tinybars; a transaction's value is denominated in weibars.
      value: tinybarsToWeibars(tinybars),
    });
    await refetchToken();
  };

  if (isDiamondLoading || sale.isLoading) {
    return <div className="h-64 rounded-2xl bg-base-200 animate-pulse" aria-hidden />;
  }

  if (!diamond) return <DiamondNotDeployed />;

  if (!sale.isLaunched) {
    return (
      <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300 text-center">
        <h2 className="font-bold text-xl m-0">No token on sale yet</h2>
        <p className="text-base-content/70 m-0 mt-2">
          The diamond is deployed, but its admin has not launched a sale. Connect the admin wallet to create the token.
        </p>
      </div>
    );
  }

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="font-bold text-xl m-0">
          {name ?? "Token"} <span className="text-base-content/60 font-normal">{symbol}</span>
        </h2>
        <div className="flex flex-wrap gap-2">
          {bonusBps !== undefined && <span className="badge badge-secondary">+{formatAmount(bonusBps, 2)}% bonus</span>}
          <span className="badge badge-primary badge-outline">
            ${formatAmount(sale.priceUsd, 18)} per {symbol ?? "token"}
          </span>
        </div>
      </div>

      <dl className="grid grid-cols-2 md:grid-cols-4 gap-4 my-6 text-sm">
        <Stat label="HBAR / USD (Chainlink)" value={hbarUsd !== undefined ? `$${formatAmount(hbarUsd, 18)}` : "…"} />
        <Stat label="Available" value={typeof available === "bigint" ? formatAmount(available, sale.decimals) : "…"} />
        <Stat label="Sold" value={formatAmount(sale.sold, sale.decimals)} />
        <Stat label="Raised" value={`${formatAmount(sale.raised, TINYBAR_DECIMALS)} HBAR`} />
      </dl>

      <label className="text-sm font-medium" htmlFor="hbar-amount">
        Pay with HBAR
      </label>
      <HbarInput name="hbar-amount" placeholder="0.0" onValueChange={({ valueInNative }) => setHbar(valueInNative)} />
      <p className="text-sm text-base-content/70 mt-2 mb-4">
        {quote !== undefined ? `You receive about ${formatAmount(quote, sale.decimals)} ${symbol ?? ""}` : " "}
      </p>

      <div className="flex flex-wrap items-center gap-3">
        {address && isAssociated !== true && (
          <button className="btn btn-secondary btn-sm" onClick={associate} disabled={isAssociating}>
            {isAssociating && <span className="loading loading-spinner loading-xs" />}
            1. Associate {symbol ?? "token"}
          </button>
        )}
        <button className="btn btn-primary btn-sm" onClick={buy} disabled={!address || quote === undefined || isBuying}>
          {isAssociated === true ? "Buy" : "2. Buy"}
        </button>
        {address && typeof owned === "bigint" && (
          <span className="text-sm text-base-content/70">
            You hold {formatAmount(owned, sale.decimals)} {symbol}
          </span>
        )}
      </div>

      {address && isAssociated !== true && (
        <p className="text-xs text-base-content/60 mt-4 mb-0">
          On Hedera an account must associate with a token before it can receive it. Need testnet HBAR?{" "}
          <HederaPortalFaucet variant="link" label="Use the faucet" showIcon={false} />
        </p>
      )}
    </div>
  );
};

const Stat = ({ label, value }: { label: string; value: string }) => (
  <div>
    <dt className="text-base-content/60">{label}</dt>
    <dd className="m-0 font-semibold">{value}</dd>
  </div>
);
