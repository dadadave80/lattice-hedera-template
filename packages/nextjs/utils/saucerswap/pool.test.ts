import {
  deadlineAfter,
  differenceBps,
  fitsInt64,
  hbarToSend,
  maxCreationFee,
  parseSlippageBps,
  poolPriceUsd,
  salePriceUsd,
  seedMinimums,
  tokensAtPoolRatio,
} from "./pool";
import { parseUnits } from "viem";
import { describe, expect, it } from "vitest";

describe("poolPriceUsd", () => {
  it("prices one whole token in 18-decimal USD from the reserves and HBAR/USD", () => {
    // 100 HBAR against 2,000 tokens is 0.05 HBAR a token; at $0.10 per HBAR that is $0.005.
    expect(poolPriceUsd(parseUnits("2000", 8), parseUnits("100", 8), 8, parseUnits("0.1", 18))).toBe(
      parseUnits("0.005", 18),
    );
  });

  it("scales by the token's decimals", () => {
    expect(poolPriceUsd(parseUnits("2000", 2), parseUnits("100", 8), 2, parseUnits("0.1", 18))).toBe(
      parseUnits("0.005", 18),
    );
  });

  it("is undefined while either reserve is empty", () => {
    expect(poolPriceUsd(0n, 1n, 8, 1n)).toBeUndefined();
    expect(poolPriceUsd(1n, 0n, 8, 1n)).toBeUndefined();
  });
});

describe("salePriceUsd", () => {
  it("prices one whole token from what 1 HBAR buys", () => {
    // At $0.10 per HBAR, 20 tokens for 1 HBAR is $0.005 a token.
    expect(salePriceUsd(parseUnits("20", 8), 8, parseUnits("0.1", 18))).toBe(parseUnits("0.005", 18));
  });

  it("drops by the bonus when 1 HBAR buys 5% more", () => {
    expect(salePriceUsd(parseUnits("21", 8), 8, parseUnits("0.1", 18))).toBe(4_761_904_761_904_761n);
  });

  it("is undefined when 1 HBAR buys nothing", () => {
    expect(salePriceUsd(0n, 8, 1n)).toBeUndefined();
  });
});

describe("differenceBps", () => {
  it("is positive above the reference and negative below it", () => {
    expect(differenceBps(105n, 100n)).toBe(500n);
    expect(differenceBps(95n, 100n)).toBe(-500n);
  });

  it("is undefined against a zero reference", () => {
    expect(differenceBps(1n, 0n)).toBeUndefined();
  });
});

describe("tokensAtPoolRatio", () => {
  it("matches the pool's ratio", () => {
    expect(tokensAtPoolRatio(50n, 2000n, 100n)).toBe(1000n);
  });

  it("is 0 for an empty pool", () => {
    expect(tokensAtPoolRatio(50n, 2000n, 0n)).toBe(0n);
  });
});

describe("parseSlippageBps", () => {
  it("parses a percentage into basis points", () => {
    expect(parseSlippageBps("1")).toBe(100n);
    expect(parseSlippageBps(" 0.5 ")).toBe(50n);
    expect(parseSlippageBps("0")).toBe(0n);
  });

  it("refuses anything that is not a percentage below 100", () => {
    expect(parseSlippageBps("")).toBeUndefined();
    expect(parseSlippageBps("abc")).toBeUndefined();
    expect(parseSlippageBps("-1")).toBeUndefined();
    expect(parseSlippageBps("100")).toBeUndefined();
  });
});

describe("seedMinimums", () => {
  it("takes the slippage off both amounts", () => {
    expect(seedMinimums(10_000n, 2_000n, 100n)).toEqual({ minTokens: 9_900n, minTinybars: 1_980n });
  });

  it("never goes below 1, which seedPool would refuse", () => {
    expect(seedMinimums(1n, 50n, 9_900n)).toEqual({ minTokens: 1n, minTinybars: 1n });
  });
});

describe("maxCreationFee", () => {
  it("adds a 5% margin, rounded up", () => {
    expect(maxCreationFee(1_938_792_326n)).toBe(2_035_731_943n);
    expect(maxCreationFee(100n)).toBe(105n);
    expect(maxCreationFee(0n)).toBe(0n);
  });
});

describe("fitsInt64", () => {
  it("accepts amounts up to the int64 maximum", () => {
    expect(fitsInt64(2n ** 63n - 1n)).toBe(true);
    expect(fitsInt64(2n ** 63n)).toBe(false);
    expect(fitsInt64(-1n)).toBe(false);
  });
});

describe("hbarToSend", () => {
  it("sends only what the diamond's proceeds do not cover", () => {
    expect(hbarToSend(1_000n, 200n, 700n, true)).toBe(500n);
    expect(hbarToSend(1_000n, 200n, 5_000n, true)).toBe(0n);
  });

  it("sends the amount and the fee in full when the proceeds are left alone", () => {
    expect(hbarToSend(1_000n, 200n, 5_000n, false)).toBe(1_200n);
  });
});

describe("deadlineAfter", () => {
  it("gives Unix seconds the given minutes from now", () => {
    expect(deadlineAfter(1_700_000_000_500, 20)).toBe(1_700_001_200n);
  });
});
