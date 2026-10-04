"use client";

import { useState } from "react";
import { HbarInput } from "@scaffold-hbar-ui/components";
import { erc20Abi, formatUnits, zeroAddress } from "viem";
import { useAccount, useConfig, useEstimateFeesPerGas, useReadContract, useWriteContract } from "wagmi";
import {
  useDeployedContractInfo,
  useScaffoldReadContract,
  useTargetNetwork,
  useTransactor,
} from "~~/hooks/scaffold-hbar";
import { useSale } from "~~/hooks/useSale";
import { useWatchedBalance } from "~~/hooks/useWatchedBalance";
import {
  TINYBAR_DECIMALS,
  formatAmount,
  hbarToTinybars,
  parsePositive,
  tinybarsToWeibars,
  weibarsToTinybars,
} from "~~/utils/sale/units";
import { PoolInfo, saucerSwapPoolAbi } from "~~/utils/saucerswap/abi";
import {
  deadlineAfter,
  fitsInt64,
  hbarToSend,
  maxCreationFee,
  parseSlippageBps,
  seedMinimums,
  tokensAtPoolRatio,
} from "~~/utils/saucerswap/pool";
import { AllowedChainIds } from "~~/utils/scaffold-hbar";
import { simulateContractWriteAndNotifyError } from "~~/utils/scaffold-hbar/contract";

/**
 * Creating a pool used 6.8M gas on testnet and 7.5M on mainnet when a wallet called the router directly. The diamond
 * adds an HTS approve and its own dispatch, and the relay refuses a limit over 15M.
 */
const NEW_POOL_GAS = 12_000_000n;
/**
 * Adding to an existing pool used 224k to 973k gas on testnet from a wallet. The diamond adds up to two HTS approves and may
 * associate itself with the LP token.
 */
const EXISTING_POOL_GAS = 2_500_000n;
const DEFAULT_SLIPPAGE = "1";
const DEFAULT_DEADLINE_MINUTES = "20";

type PoolSeedFormProps = { pool: PoolInfo; symbol: string };

/** The admin's form for `seedPool`: creates the pool, or adds to it, from the diamond's tokens and HBAR. */
export const PoolSeedForm = ({ pool, symbol }: PoolSeedFormProps) => {
  const { address } = useAccount();
  const { targetNetwork } = useTargetNetwork();
  const sale = useSale();
  const { data: diamond } = useDeployedContractInfo({ contractName: "Diamond" });
  const [hbar, setHbar] = useState("");
  const [typedTokens, setTypedTokens] = useState<string>();
  const [slippage, setSlippage] = useState(DEFAULT_SLIPPAGE);
  const [deadlineMinutes, setDeadlineMinutes] = useState(DEFAULT_DEADLINE_MINUTES);
  const [useProceeds, setUseProceeds] = useState(true);
  const [isSeeding, setIsSeeding] = useState(false);

  const isNewPool = pool.pair === zeroAddress;
  const tinybars = hbarToTinybars(hbar);
  const { data: quote } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "quote",
    args: [tinybars],
    query: { enabled: isNewPool && tinybars !== undefined },
  });
  // A new pool opens at the ratio given, so the default matches what buyers pay; an existing one takes its own ratio.
  const suggestedTokens =
    tinybars === undefined
      ? undefined
      : isNewPool
        ? quote
        : tokensAtPoolRatio(tinybars, pool.reserveTokens, pool.reserveTinybars);
  const tokens = typedTokens !== undefined ? parsePositive(typedTokens, sale.decimals) : suggestedTokens || undefined;
  const slippageBps = parseSlippageBps(slippage);
  const minutes = Number(deadlineMinutes);
  const isDeadlineValid = Number.isFinite(minutes) && minutes > 0;
  const minimums =
    tokens !== undefined && tinybars !== undefined && slippageBps !== undefined
      ? seedMinimums(tokens, tinybars, slippageBps)
      : undefined;

  const { data: isStopped } = useScaffoldReadContract({ contractName: "Diamond", functionName: "isStopped" });
  const { data: diamondTokens, refetch: refetchDiamondTokens } = useReadContract({
    chainId: targetNetwork.id,
    address: sale.token,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [diamond?.address ?? zeroAddress],
    query: { enabled: sale.isLaunched && diamond !== undefined },
  });
  const { data: diamondBalance } = useWatchedBalance(diamond?.address);
  const { data: walletBalance } = useWatchedBalance(address);
  const { data: feesPerGas } = useEstimateFeesPerGas({ chainId: targetNetwork.id });

  const maxFee = isNewPool ? maxCreationFee(pool.creationFee) : 0n;
  const diamondTinybars = diamondBalance ? weibarsToTinybars(diamondBalance.value) : undefined;
  const send =
    tinybars === undefined || diamondTinybars === undefined
      ? undefined
      : hbarToSend(tinybars, maxFee, diamondTinybars, useProceeds);
  const gas = isNewPool ? NEW_POOL_GAS : EXISTING_POOL_GAS;
  // The wallet must hold the value plus the whole gas limit's fee up front, at what it offers per gas.
  const required =
    send === undefined || feesPerGas === undefined
      ? undefined
      : tinybarsToWeibars(send) + gas * (feesPerGas.maxFeePerGas + feesPerGas.maxPriorityFeePerGas);
  const isShortOfHbar = walletBalance !== undefined && required !== undefined && walletBalance.value < required;
  const isTooLarge = tokens !== undefined && !fitsInt64(tokens);
  const isShortOfTokens = tokens !== undefined && diamondTokens !== undefined && tokens > diamondTokens;

  const wagmiConfig = useConfig();
  const transactor = useTransactor();
  const { writeContractAsync } = useWriteContract();

  const canSeed =
    address !== undefined &&
    diamond !== undefined &&
    isStopped !== true &&
    tokens !== undefined &&
    tinybars !== undefined &&
    minimums !== undefined &&
    send !== undefined &&
    isDeadlineValid &&
    !isTooLarge &&
    !isShortOfTokens &&
    !isShortOfHbar &&
    !isSeeding;

  const seed = async () => {
    if (!canSeed || !diamond || tokens === undefined || tinybars === undefined || !minimums || send === undefined) {
      return;
    }
    const request = {
      chainId: targetNetwork.id,
      address: diamond.address,
      abi: saucerSwapPoolAbi,
      functionName: "seedPool",
      args: [tokens, tinybars, minimums.minTokens, minimums.minTinybars, maxFee, deadlineAfter(Date.now(), minutes)],
      // The contract sees tinybars; a transaction's value is denominated in weibars.
      value: tinybarsToWeibars(send),
      gas,
    } as const;
    try {
      setIsSeeding(true);
      await simulateContractWriteAndNotifyError({
        wagmiConfig,
        writeContractParams: request,
        chainId: targetNetwork.id as AllowedChainIds,
      });
      const hash = await transactor(() => writeContractAsync(request));
      if (hash) {
        setHbar("");
        setTypedTokens(undefined);
        await refetchDiamondTokens();
      }
    } catch {
      // The simulation or the transactor has already shown the error.
    } finally {
      setIsSeeding(false);
    }
  };

  return (
    <div className="border-t border-base-300 mt-6 pt-6">
      <h3 className="font-bold text-lg m-0">{isNewPool ? "Create the pool" : "Add to the pool"}</h3>
      <p className="text-sm text-base-content/70 mt-1">
        {isNewPool
          ? `You hold the admin role. The diamond creates the ${symbol}/WHBAR pool from its own tokens and HBAR, opens it at the ratio you enter, and keeps the LP tokens.`
          : "You hold the admin role. The diamond adds its tokens and HBAR at the pool's current ratio and keeps the LP tokens. HBAR the pool does not take stays in the diamond."}
      </p>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">HBAR to add</span>
          <HbarInput
            name="pool-hbar-amount"
            placeholder="0.0"
            onValueChange={({ valueInNative }) => setHbar(valueInNative)}
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">
            {symbol} to add (the diamond holds{" "}
            {diamondTokens !== undefined ? formatAmount(diamondTokens, sale.decimals) : "…"})
          </span>
          <input
            className="input input-bordered w-full"
            placeholder="0"
            value={typedTokens ?? (suggestedTokens ? formatUnits(suggestedTokens, sale.decimals) : "")}
            onChange={event => setTypedTokens(event.target.value)}
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Slippage (%)</span>
          <input
            className="input input-bordered w-full"
            value={slippage}
            onChange={event => setSlippage(event.target.value)}
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Deadline (minutes from sending)</span>
          <input
            className="input input-bordered w-full"
            value={deadlineMinutes}
            onChange={event => setDeadlineMinutes(event.target.value)}
          />
        </label>
        <label className="flex items-center gap-2 text-sm md:col-span-2">
          <input
            type="checkbox"
            className="checkbox checkbox-sm"
            checked={useProceeds}
            onChange={event => setUseProceeds(event.target.checked)}
          />
          <span>
            Pay from the diamond&apos;s HBAR first (it holds{" "}
            {diamondTinybars !== undefined ? formatAmount(diamondTinybars, TINYBAR_DECIMALS) : "…"} HBAR, sale proceeds
            included)
          </span>
        </label>
      </div>

      <ul className="text-sm text-base-content/70 mt-4 mb-4 pl-5 list-disc">
        {typedTokens !== undefined && (
          <li>
            <button className="link" onClick={() => setTypedTokens(undefined)}>
              {isNewPool ? "Use the sale's price" : "Use the pool's ratio"}
            </button>
          </li>
        )}
        {isNewPool && (
          <li>
            Creation fee: {formatAmount(pool.creationFee, TINYBAR_DECIMALS)} HBAR now. The call allows up to{" "}
            {formatAmount(maxFee, TINYBAR_DECIMALS)} HBAR in case the exchange rate moves, and pays only the fee.
          </li>
        )}
        {minimums && (
          <li>
            The call reverts if the pool would take fewer than {formatAmount(minimums.minTokens, sale.decimals)}{" "}
            {symbol} or {formatAmount(minimums.minTinybars, TINYBAR_DECIMALS)} HBAR
            {isNewPool && ", which happens if someone creates the pool at another price first"}.
          </li>
        )}
        {send !== undefined && (
          <li>
            Sends {formatAmount(send, TINYBAR_DECIMALS)} HBAR from your wallet
            {required !== undefined && `, which must hold ${formatAmount(required, 18)} HBAR with the network fee`}.
            Unspent HBAR stays in the diamond.
          </li>
        )}
      </ul>

      <button className="btn btn-primary btn-sm" onClick={seed} disabled={!canSeed}>
        {isSeeding && <span className="loading loading-spinner loading-xs" />}
        {isNewPool ? "Create the pool" : "Add liquidity"}
      </button>

      {isStopped && (
        <p className="text-sm text-warning mt-4 mb-0">The emergency stop is on, so the diamond cannot seed the pool.</p>
      )}
      {isTooLarge && (
        <p className="text-sm text-warning mt-4 mb-0">HTS cannot move that many token units in one call.</p>
      )}
      {isShortOfTokens && (
        <p className="text-sm text-warning mt-4 mb-0">
          The diamond holds only {formatAmount(diamondTokens, sale.decimals)} {symbol}.
        </p>
      )}
      {typedTokens !== undefined && tokens === undefined && (
        <p className="text-sm text-warning mt-4 mb-0">Enter a positive token amount.</p>
      )}
      {slippageBps === undefined && (
        <p className="text-sm text-warning mt-4 mb-0">Slippage must be from 0 to below 100%.</p>
      )}
      {!isDeadlineValid && (
        <p className="text-sm text-warning mt-4 mb-0">The deadline must be a positive number of minutes.</p>
      )}
      {isShortOfHbar && walletBalance && (
        <p className="text-sm text-warning mt-4 mb-0">
          Not enough HBAR: this wallet holds {formatAmount(walletBalance.value, walletBalance.decimals)} HBAR.
        </p>
      )}
    </div>
  );
};
