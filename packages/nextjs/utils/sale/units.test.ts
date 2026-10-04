import { formatAmount, formatPrice, hbarToTinybars, minTokensOut, parsePositive, tinybarsToWeibars } from "./units";
import { parseEther, parseUnits } from "viem";
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

  it("returns undefined for an amount that is zero, negative or rounds down to zero tinybars", () => {
    expect(hbarToTinybars("0.0")).toBeUndefined();
    expect(hbarToTinybars("-1")).toBeUndefined();
    expect(hbarToTinybars("0.000000004")).toBeUndefined();
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

describe("formatPrice", () => {
  it("shows a price with up to four significant digits", () => {
    expect(formatPrice(parseUnits("0.05", 18), 18)).toBe("0.05");
    expect(formatPrice(parseUnits("0.1015", 8), 8)).toBe("0.1015");
    expect(formatPrice(parseUnits("0.123456", 18), 18)).toBe("0.1235");
    expect(formatPrice(parseUnits("12.34567", 18), 18)).toBe("12.35");
  });

  it("keeps a price below a tenth of a cent from showing as zero or as a rounded-up neighbour", () => {
    expect(formatPrice(parseUnits("0.00004", 18), 18)).toBe("0.00004");
    expect(formatPrice(parseUnits("0.00006", 18), 18)).toBe("0.00006");
    expect(formatPrice(1n, 18)).toBe("0.000000000000000001");
  });

  it("carries a rounded-up digit into the next place", () => {
    expect(formatPrice(parseUnits("0.99996", 18), 18)).toBe("1");
    expect(formatPrice(parseUnits("0.000099996", 18), 18)).toBe("0.0001");
  });

  it("keeps the whole integer part exact, however large", () => {
    expect(formatPrice(parseUnits("123456.789", 18), 18)).toBe("123,457");
    expect(formatPrice(parseUnits("12345678901234567890.25", 18), 18)).toBe("12,345,678,901,234,567,890");
  });

  it("shows zero as 0", () => {
    expect(formatPrice(0n, 18)).toBe("0");
  });

  it("takes the number of significant digits", () => {
    expect(formatPrice(parseUnits("0.123456", 18), 18, 2)).toBe("0.12");
  });
});
