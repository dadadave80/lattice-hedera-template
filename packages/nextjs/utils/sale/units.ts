import { formatUnits, parseUnits } from "viem";

/**
 * Hedera has two units for HBAR, and mixing them up is the classic first bug:
 * - inside the EVM, `msg.value` and every amount the sale contract takes or returns is in tinybars (8 decimals);
 * - over JSON-RPC, a transaction's `value` is in weibars (18 decimals), and the relay converts it.
 */
export const TINYBAR_DECIMALS = 8;
const WEIBARS_PER_TINYBAR = 10_000_000_000n;
const BPS = 10_000n;

/** Parses what a user typed, e.g. "1.5", into tinybars. Undefined for anything that is not a positive amount. */
export function hbarToTinybars(hbar: string): bigint | undefined {
  return parsePositive(hbar, TINYBAR_DECIMALS);
}

/** The `value` to put on a transaction that should arrive in the contract as `tinybars`. */
export function tinybarsToWeibars(tinybars: bigint): bigint {
  return tinybars * WEIBARS_PER_TINYBAR;
}

/** Parses a decimal amount, e.g. a token count or a USD price, into its smallest unit. */
export function parsePositive(amount: string, decimals: number): bigint | undefined {
  try {
    const value = parseUnits(amount.trim(), decimals);
    return value > 0n ? value : undefined;
  } catch {
    return undefined;
  }
}

/** The fewest tokens a buyer accepts when the quote may move by `slippageBps` before the transaction lands. */
export function minTokensOut(quotedTokens: bigint, slippageBps: bigint): bigint {
  return (quotedTokens * (BPS - slippageBps)) / BPS;
}

/** Formats an amount held in its smallest unit for display, e.g. 123456789n with 8 decimals as "1.2346". */
export function formatAmount(value: bigint, decimals: number, maximumFractionDigits = 4): string {
  return Number(formatUnits(value, decimals)).toLocaleString("en-US", { maximumFractionDigits });
}

/**
 * Formats a price held in its smallest unit with up to `significantDigits` significant digits, so a positive price
 * never reads as 0. Digits past the last significant one round to zero, so a large price shows no fraction and its
 * integer part is rounded to the nearest whole number.
 */
export function formatPrice(value: bigint, decimals: number, significantDigits = 4): string {
  if (value <= 0n) return "0";
  const integerDigits = value.toString().length - decimals;
  const fractionDigits = Math.min(decimals, Math.max(0, significantDigits - integerDigits));
  const unit = 10n ** BigInt(decimals - fractionDigits);
  const [integer, fraction] = formatUnits(((value + unit / 2n) / unit) * unit, decimals).split(".");
  const grouped = BigInt(integer).toLocaleString("en-US");
  return fraction ? `${grouped}.${fraction}` : grouped;
}
