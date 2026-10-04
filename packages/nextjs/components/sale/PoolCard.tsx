"use client";

import { useEffect } from "react";
import { PoolSeedForm } from "./PoolSeedForm";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { erc20Abi, getAbiItem, toFunctionSelector, zeroAddress, zeroHash } from "viem";
import { useAccount, useBlockNumber, useReadContract } from "wagmi";
import { useDeployedContractInfo, useScaffoldReadContract, useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { useSale } from "~~/hooks/useSale";
import { TINYBAR_DECIMALS, formatAmount, formatPrice } from "~~/utils/sale/units";
import { saucerSwapPoolAbi } from "~~/utils/saucerswap/abi";
import { hashScanUrl, longZeroToEntityId, saucerSwapPoolUrl, saucerSwapUrl } from "~~/utils/saucerswap/links";
import { differenceBps, poolPriceUsd, salePriceUsd } from "~~/utils/saucerswap/pool";
import { mirrorNodeUrl } from "~~/utils/stealth/announcements";

const SEED_POOL_SELECTOR = toFunctionSelector(getAbiItem({ abi: saucerSwapPoolAbi, name: "seedPool" }));
/** Lattice's `DEFAULT_ADMIN_ROLE`. */
const ADMIN_ROLE = zeroHash;
const ONE_HBAR_IN_TINYBARS = 100_000_000n;

/** The sale's SaucerSwap V1 pool against WHBAR, and for the admin, the form that seeds it from the diamond. */
export const PoolCard = () => {
  const { address } = useAccount();
  const { targetNetwork } = useTargetNetwork();
  const sale = useSale();
  const { data: diamond } = useDeployedContractInfo({ contractName: "Diamond" });
  const {
    data: poolFacet,
    isLoading: isLoupeLoading,
    isError: isLoupeError,
  } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "facetAddress",
    args: [SEED_POOL_SELECTOR],
  });
  const hasFacet = poolFacet !== undefined && poolFacet !== zeroAddress;
  const { data: isAdmin } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "hasRole",
    args: [ADMIN_ROLE, address],
  });
  const { data: hbarUsd } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "latestAnswer",
    args: [sale.feedKey],
    query: { enabled: sale.isLaunched },
  });
  // What buyers get for 1 HBAR, so a bonus such as TokenSaleV2's counts in the price the pool is compared with.
  const { data: tokensForOneHbar } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "quote",
    args: [ONE_HBAR_IN_TINYBARS],
    query: { enabled: sale.isLaunched },
  });

  const queryClient = useQueryClient();
  const {
    data: pool,
    isError: isPoolError,
    queryKey: poolQueryKey,
  } = useReadContract({
    chainId: targetNetwork.id,
    address: diamond?.address,
    abi: saucerSwapPoolAbi,
    functionName: "poolInfo",
    query: { enabled: diamond !== undefined && hasFacet },
  });
  const { data: symbol } = useReadContract({
    chainId: targetNetwork.id,
    address: sale.token,
    abi: erc20Abi,
    functionName: "symbol",
    query: { enabled: sale.isLaunched },
  });
  const { data: blockNumber } = useBlockNumber({ watch: true, chainId: targetNetwork.id });

  useEffect(() => {
    queryClient.invalidateQueries({ queryKey: poolQueryKey });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [blockNumber]);

  const pair = pool?.pair !== undefined && pool.pair !== zeroAddress ? pool.pair : undefined;
  // A pair is deployed with CREATE2, so its `0.0.N` id, which SaucerSwap's pool page takes, comes from the mirror node.
  const { data: pairId } = useQuery({
    queryKey: ["saucerSwapPairId", targetNetwork.id, pair],
    queryFn: async () => {
      const response = await fetch(`${mirrorNodeUrl(targetNetwork.id)}/api/v1/contracts/${pair}`);
      if (!response.ok) throw new Error(`The mirror node answered ${response.status}`);
      const { contract_id } = (await response.json()) as { contract_id: string };
      return contract_id;
    },
    enabled: pair !== undefined,
    staleTime: Infinity,
  });

  if (!diamond || !sale.isLaunched) return null;

  if (isLoupeLoading) return <div className="h-48 rounded-2xl bg-base-200 animate-pulse" aria-hidden />;

  if (isLoupeError) {
    return (
      <div role="alert" className="alert alert-error">
        <span>
          The diamond&apos;s loupe did not answer, so this page cannot tell whether it has a SaucerSwap pool. Reload.
        </span>
      </div>
    );
  }

  if (!hasFacet) {
    const network = targetNetwork.id === 295 ? "hedera_mainnet" : "hedera_testnet";
    return (
      <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
        <h2 className="font-bold text-xl m-0">SaucerSwap pool</h2>
        <p className="text-base-content/70 m-0 mt-2">
          No facet serves <code>seedPool</code>, so this diamond cannot put its token and HBAR into a SaucerSwap pool
          yet. Its admin can cut in <code>SaucerSwapPool</code> with its initializer and this network&apos;s SaucerSwap
          addresses:
        </p>
        <pre className="text-sm bg-base-200 rounded-xl p-4 mt-4 overflow-x-auto">
          yarn foundry:deploy --file DeploySaucerSwapPool.s.sol --network {network}
        </pre>
      </div>
    );
  }

  const tokenId = sale.token ? longZeroToEntityId(sale.token) : undefined;
  const price =
    pool && hbarUsd !== undefined
      ? poolPriceUsd(pool.reserveTokens, pool.reserveTinybars, sale.decimals, hbarUsd)
      : undefined;
  const buyersPay =
    tokensForOneHbar !== undefined && hbarUsd !== undefined
      ? salePriceUsd(tokensForOneHbar, sale.decimals, hbarUsd)
      : undefined;
  const difference = price !== undefined && buyersPay !== undefined ? differenceBps(price, buyersPay) : undefined;
  const share = pool && pool.lpTotalSupply > 0n ? (pool.lpBalance * 10_000n) / pool.lpTotalSupply : undefined;
  const ticker = symbol ?? "token";

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="font-bold text-xl m-0">SaucerSwap pool</h2>
        {pool && (
          <span className={`badge ${pair ? "badge-success" : "badge-ghost"}`}>
            {pair ? `${ticker}/WHBAR pool open` : "No pool yet"}
          </span>
        )}
      </div>

      {isPoolError ? (
        <p className="text-sm text-error m-0 mt-4">Could not read the pool from the diamond.</p>
      ) : !pool ? (
        <div className="h-24 rounded-xl bg-base-200 animate-pulse mt-4" aria-hidden />
      ) : pair ? (
        <dl className="grid grid-cols-2 md:grid-cols-4 gap-4 my-6 text-sm">
          <Stat label={`${ticker} in the pool`} value={formatAmount(pool.reserveTokens, sale.decimals)} />
          <Stat label="HBAR in the pool" value={`${formatAmount(pool.reserveTinybars, TINYBAR_DECIMALS)} HBAR`} />
          <Stat
            label={`Pool price per ${ticker}`}
            value={price !== undefined ? `$${formatPrice(price, 18)}` : pool.reserveTokens === 0n ? "Empty" : "…"}
          />
          <Stat
            label={`Sale price buyers pay per ${ticker}`}
            value={`${buyersPay !== undefined ? `$${formatPrice(buyersPay, 18)}` : "…"}${
              difference !== undefined ? ` · pool ${difference >= 0n ? "+" : ""}${formatAmount(difference, 2, 2)}%` : ""
            }`}
          />
          <Stat
            label="Diamond's LP tokens"
            value={`${formatAmount(pool.lpBalance, 8)}${share !== undefined ? ` (${formatAmount(share, 2, 2)}%)` : ""}`}
          />
        </dl>
      ) : (
        <p className="text-sm text-base-content/70 m-0 mt-2 mb-4">
          Nobody has created a {ticker}/WHBAR pool on SaucerSwap. Until someone does, the sale is the only place to buy{" "}
          {ticker}. Creating the pool costs {formatAmount(pool.creationFee, TINYBAR_DECIMALS)} HBAR at today&apos;s
          exchange rate, on top of the liquidity.
        </p>
      )}

      <div className="flex flex-wrap gap-4 text-sm">
        {pairId ? (
          <a className="link" href={saucerSwapPoolUrl(targetNetwork.id, pairId)} target="_blank" rel="noreferrer">
            Pool on SaucerSwap
          </a>
        ) : (
          <a className="link" href={saucerSwapUrl(targetNetwork.id)} target="_blank" rel="noreferrer">
            SaucerSwap
          </a>
        )}
        {pair && (
          <a
            className="link"
            href={hashScanUrl(targetNetwork.id, "contract", pairId ?? pair)}
            target="_blank"
            rel="noreferrer"
          >
            Pair on HashScan
          </a>
        )}
        {sale.token && (
          <a
            className="link"
            href={hashScanUrl(targetNetwork.id, "token", tokenId ?? sale.token)}
            target="_blank"
            rel="noreferrer"
          >
            {ticker} on HashScan
          </a>
        )}
      </div>

      {isAdmin && pool && <PoolSeedForm pool={pool} symbol={ticker} />}
    </div>
  );
};

const Stat = ({ label, value }: { label: string; value: string }) => (
  <div>
    <dt className="text-base-content/60">{label}</dt>
    <dd className="m-0 font-semibold">{value}</dd>
  </div>
);
