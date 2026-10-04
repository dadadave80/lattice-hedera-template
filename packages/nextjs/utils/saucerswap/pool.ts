import { TINYBAR_DECIMALS } from "~~/utils/sale/units";

const BPS = 10_000n;
const INT64_MAX = 2n ** 63n - 1n;
/** How much the creation fee may rise, in basis points, between reading it and the transaction landing. */
export const CREATION_FEE_MARGIN_BPS = 500n;

/**
 * The pool's price of one whole token in USD with 18 decimals, from its reserves and the Chainlink HBAR/USD answer (18
 * decimals), so it compares directly with the sale's `priceUsd`. Undefined while the pool is empty.
 */
export function poolPriceUsd(
  reserveTokens: bigint,
  reserveTinybars: bigint,
  tokenDecimals: number,
  hbarUsd: bigint,
): bigint | undefined {
  if (reserveTokens === 0n || reserveTinybars === 0n) return undefined;
  return (reserveTinybars * 10n ** BigInt(tokenDecimals) * hbarUsd) / (reserveTokens * 10n ** BigInt(TINYBAR_DECIMALS));
}

/**
 * The price of one whole token in USD with 18 decimals that buyers pay the sale, from what `quote` gives for 1 HBAR and
 * the Chainlink HBAR/USD answer (18 decimals). It counts any bonus the sale facet adds, which `priceUsd` does not.
 */
export function salePriceUsd(tokensForOneHbar: bigint, tokenDecimals: number, hbarUsd: bigint): bigint | undefined {
  if (tokensForOneHbar === 0n) return undefined;
  return (hbarUsd * 10n ** BigInt(tokenDecimals)) / tokensForOneHbar;
}

/** How far `price` sits above (positive) or below (negative) `reference`, in basis points. */
export function differenceBps(price: bigint, reference: bigint): bigint | undefined {
  if (reference === 0n) return undefined;
  return ((price - reference) * BPS) / reference;
}

/** The token units that go with `tinybars` at the pool's current ratio, as the router computes them. */
export function tokensAtPoolRatio(tinybars: bigint, reserveTokens: bigint, reserveTinybars: bigint): bigint {
  if (reserveTinybars === 0n) return 0n;
  return (tinybars * reserveTokens) / reserveTinybars;
}

/** Parses a slippage percentage, e.g. "1" or "0.5", into basis points. Undefined unless it is at least 0 and below 100. */
export function parseSlippageBps(percent: string): bigint | undefined {
  const trimmed = percent.trim();
  const value = Number(trimmed);
  if (trimmed === "" || !Number.isFinite(value) || value < 0 || value >= 100) return undefined;
  return BigInt(Math.round(value * 100));
}

/** The fewest token units and tinybars the router may add. `seedPool` refuses a zero minimum, so neither goes below 1. */
export function seedMinimums(
  tokens: bigint,
  tinybars: bigint,
  slippageBps: bigint,
): { minTokens: bigint; minTinybars: bigint } {
  const floor = (amount: bigint) => {
    const min = (amount * (BPS - slippageBps)) / BPS;
    return min > 0n ? min : 1n;
  };
  return { minTokens: floor(tokens), minTinybars: floor(tinybars) };
}

/** The `maxCreationFee` to pass: the current fee plus the margin, rounded up. The call pays only the fee itself. */
export function maxCreationFee(fee: bigint): bigint {
  return (fee * (BPS + CREATION_FEE_MARGIN_BPS) + BPS - 1n) / BPS;
}

/** True when `amount` fits the `int64` HTS takes for token amounts. */
export function fitsInt64(amount: bigint): boolean {
  return amount >= 0n && amount <= INT64_MAX;
}

/**
 * The tinybars the wallet sends with `seedPool`. The facet adds the call's value to the diamond's balance, then needs
 * `tinybars` plus a creation fee that only `maxFee` bounds. With `useProceeds`, the diamond's own HBAR covers what it
 * can. Whatever the call does not spend stays in the diamond.
 */
export function hbarToSend(tinybars: bigint, maxFee: bigint, diamondTinybars: bigint, useProceeds: boolean): bigint {
  const needed = tinybars + maxFee;
  if (!useProceeds) return needed;
  return needed > diamondTinybars ? needed - diamondTinybars : 0n;
}

/** The router's `deadline`: Unix seconds, `minutes` after `nowMs`. */
export function deadlineAfter(nowMs: number, minutes: number): bigint {
  return BigInt(Math.floor(nowMs / 1000) + Math.round(minutes * 60));
}
