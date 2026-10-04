"use client";

import { useEffect, useState } from "react";
import { HbarInput, HederaPortalFaucet } from "@scaffold-hbar-ui/components";
import { useQueryClient } from "@tanstack/react-query";
import { erc20Abi, formatUnits, parseAbi, zeroAddress } from "viem";
import {
  useAccount,
  useBalance,
  useBlockNumber,
  useEstimateFeesPerGas,
  useReadContract,
  useReadContracts,
  useWriteContract,
} from "wagmi";
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
import {
  TINYBAR_DECIMALS,
  formatAmount,
  formatPrice,
  hbarToTinybars,
  minTokensOut,
  tinybarsToWeibars,
} from "~~/utils/sale/units";

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

  const { data: isStopped } = useScaffoldReadContract({ contractName: "Diamond", functionName: "isStopped" });

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

  const queryClient = useQueryClient();
  const {
    data: bonusBps,
    isError: isBonusError,
    queryKey: bonusQueryKey,
  } = useReadContract({
    chainId: targetNetwork.id,
    address: diamond?.address,
    abi: bonusAbi,
    functionName: "bonusBps",
    query: { enabled: diamond !== undefined, retry: false },
  });
  const { data: walletBalance, queryKey: walletBalanceQueryKey } = useBalance({
    address,
    chainId: targetNetwork.id,
    query: { enabled: address !== undefined },
  });
  const { data: blockNumber } = useBlockNumber({ watch: true, chainId: targetNetwork.id });

  useEffect(() => {
    queryClient.invalidateQueries({ queryKey: bonusQueryKey });
    queryClient.invalidateQueries({ queryKey: walletBalanceQueryKey });
    // refetch() ignores `enabled`, so each read is refreshed only once it has something to read.
    if (sale.isLaunched && diamond) refetchToken();
    if (sale.isLaunched && address) refetchAssociation();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [blockNumber]);

  // The relay cannot simulate a transaction from an address Hedera has no account for, and an
  // address only gets one when it first receives HBAR.
  const isUnfunded = walletBalance?.value === 0n;
  // A wallet that holds the token is associated, even when the read has not caught up with a buy that associated it.
  const needsAssociation =
    address !== undefined && isAssociated === false && !(typeof owned === "bigint" && owned > 0n);
  // The wallet must hold the payment plus the whole gas limit's fee up front. On testnet `buy` used 799,317 gas when it
  // associated the buyer with the token and 93,893 gas after; these limits leave the margin wallets add.
  const { data: feesPerGas } = useEstimateFeesPerGas({ chainId: targetNetwork.id });
  const buyGas = isAssociated === true ? 110_000n : 900_000n;
  const required =
    tinybars === undefined || feesPerGas === undefined
      ? undefined
      : tinybarsToWeibars(tinybars) + buyGas * (feesPerGas.maxFeePerGas + feesPerGas.maxPriorityFeePerGas);
  const isShortOfHbar =
    !isUnfunded && walletBalance !== undefined && required !== undefined && walletBalance.value < required;
  const isShortOfTokens = quote !== undefined && typeof available === "bigint" && quote > available;
  const minTokens = quote !== undefined ? minTokensOut(quote, SLIPPAGE_BPS) : undefined;

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
    } catch {
      // The transactor has already shown the error.
    } finally {
      setIsAssociating(false);
    }
  };

  const buy = async () => {
    if (tinybars === undefined || minTokens === undefined) return;
    try {
      await writeDiamond({
        functionName: "buy",
        args: [minTokens],
        // The contract sees tinybars; a transaction's value is denominated in weibars.
        value: tinybarsToWeibars(tinybars),
      });
      await Promise.all([refetchToken(), refetchAssociation()]);
    } catch {
      // The simulation or the transactor has already shown the error.
    }
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
          {bonusBps !== undefined && !isBonusError && (
            <span className="badge badge-secondary">+{formatAmount(bonusBps, 2)}% bonus</span>
          )}
          <span className="badge badge-primary badge-outline">
            ${formatPrice(sale.priceUsd, 18)} per {symbol ?? "token"}
          </span>
        </div>
      </div>

      <dl className="grid grid-cols-2 md:grid-cols-4 gap-4 my-6 text-sm">
        <Stat label="HBAR / USD (Chainlink)" value={hbarUsd !== undefined ? `$${formatPrice(hbarUsd, 18)}` : "…"} />
        <Stat label="Available" value={typeof available === "bigint" ? formatAmount(available, sale.decimals) : "…"} />
        <Stat label="Sold" value={formatAmount(sale.sold, sale.decimals)} />
        <Stat label="Raised" value={`${formatAmount(sale.raised, TINYBAR_DECIMALS)} HBAR`} />
      </dl>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Pay with HBAR</span>
        <HbarInput name="hbar-amount" placeholder="0.0" onValueChange={({ valueInNative }) => setHbar(valueInNative)} />
      </label>
      <p className="text-sm text-base-content/70 mt-2 mb-4">
        Sends {formatUnits(tinybars ?? 0n, TINYBAR_DECIMALS)} HBAR
        {quote !== undefined && ` · You receive about ${formatAmount(quote, sale.decimals)} ${symbol ?? ""}`}
        {minTokens !== undefined &&
          ` · at least ${formatAmount(minTokens, sale.decimals)} ${symbol ?? ""} (${formatAmount(SLIPPAGE_BPS, 2)}% slippage)`}
      </p>

      <div className="flex flex-wrap items-center gap-3">
        {needsAssociation && (
          <button className="btn btn-secondary btn-sm" onClick={associate} disabled={isAssociating || isUnfunded}>
            {isAssociating && <span className="loading loading-spinner loading-xs" />}
            1. Associate {symbol ?? "token"}
          </button>
        )}
        <button
          className="btn btn-primary btn-sm"
          onClick={buy}
          disabled={
            !address ||
            isUnfunded ||
            isShortOfHbar ||
            isShortOfTokens ||
            tinybars === undefined ||
            quote === undefined ||
            isBuying ||
            isStopped === true
          }
        >
          {needsAssociation ? "2. Buy" : "Buy"}
        </button>
        {address && typeof owned === "bigint" && (
          <span className="text-sm text-base-content/70">
            You hold {formatAmount(owned, sale.decimals)} {symbol}
          </span>
        )}
      </div>

      {isStopped && <p className="text-sm text-warning mt-4 mb-0">Sales are paused.</p>}
      {isShortOfHbar && (
        <p className="text-sm text-warning mt-4 mb-0">
          Not enough HBAR: this purchase needs {formatAmount(required, 18)} HBAR including the network fee, and this
          wallet holds {formatAmount(walletBalance.value, walletBalance.decimals)} HBAR.
        </p>
      )}
      {isShortOfTokens && (
        <p className="text-sm text-warning mt-4 mb-0">
          {available === 0n
            ? "The sale is sold out."
            : `Only ${formatAmount(available, sale.decimals)} ${symbol ?? "tokens"} left.`}
        </p>
      )}

      {isUnfunded ? (
        <p className="text-sm text-warning mt-4 mb-0">
          This wallet holds no HBAR, so it cannot pay for a transaction. A wallet that has never received HBAR does not
          exist on Hedera yet. Fund it first:{" "}
          <HederaPortalFaucet variant="link" label="Use the faucet" showIcon={false} />
        </p>
      ) : (
        needsAssociation && (
          <p className="text-xs text-base-content/60 mt-4 mb-0">
            On Hedera an account must associate with a token before it can receive it. Need testnet HBAR?{" "}
            <HederaPortalFaucet variant="link" label="Use the faucet" showIcon={false} />
          </p>
        )
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
