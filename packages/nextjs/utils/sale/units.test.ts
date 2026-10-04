import { formatAmount, hbarToTinybars, minTokensOut, parsePositive, tinybarsToWeibars } from "./units";
import { parseEther } from "viem";
import { describe, expect, it } from "vitest";

describe("hbarToTinybars", () => {
  it("parses a decimal HBAR amount into 8-decimal tinybars", () => {
    expect(hbarToTinybars("1.5")).toBe(150_000_000n);
  });

  it("returns undefined for input that is not a positive amount", () => {
    expect(hbarToTinybars("")).toBeUndefined();
    expect(hbarToTinybars("0")).toBeUndefined();
    expect(hbarToTinybars("abc")).toBeUndefined();
  });

  it("rounds away more precision than a tinybar holds", () => {
    expect(hbarToTinybars("0.000000019")).toBe(2n);
  });
});

describe("tinybarsToWeibars", () => {
  it("gives the 18-decimal value a wallet sends for that many tinybars", () => {
    expect(tinybarsToWeibars(150_000_000n)).toBe(parseEther("1.5"));
  });
});

describe("parsePositive", () => {
  it("scales by the given decimals", () => {
    expect(parsePositive("0.05", 18)).toBe(50_000_000_000_000_000n);
    expect(parsePositive(" 1000 ", 8)).toBe(100_000_000_000n);
  });
});

describe("minTokensOut", () => {
  it("takes the slippage off the quote", () => {
    expect(minTokensOut(400_000_000n, 100n)).toBe(396_000_000n);
  });

  it("keeps the whole quote at zero slippage", () => {
    expect(minTokensOut(400_000_000n, 0n)).toBe(400_000_000n);
  });
});

describe("formatAmount", () => {
  it("shows an amount in whole units with a few decimals", () => {
    expect(formatAmount(123_456_789n, 8)).toBe("1.2346");
    expect(formatAmount(100_000_000_000_000n, 8)).toBe("1,000,000");
  });

  it("takes the number of decimals to show", () => {
    expect(formatAmount(50_000_000_000_000_000n, 18, 2)).toBe("0.05");
  });
});
