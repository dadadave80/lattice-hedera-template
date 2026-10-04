import { selectorNames } from "./selectorNames";
import { parseAbi } from "viem";
import { describe, expect, it } from "vitest";

describe("selectorNames", () => {
  it("names the functions of every ABI it is given", () => {
    const names = selectorNames([
      parseAbi(["function buy(int64 minTokens) payable returns (int64)", "event SalePriceSet(uint256 priceUsd)"]),
      parseAbi(["function bonusBps() pure returns (uint256)"]),
    ]);

    expect(names.get("0x08bf598d")).toBe("buy");
    expect(names.get("0x404f21a5")).toBe("bonusBps");
    expect(names.size).toBe(3);
  });

  it("names the selector a diamond routes plain transfers through", () => {
    expect(selectorNames([]).get("0x00000000")).toBe("receive");
  });
});
