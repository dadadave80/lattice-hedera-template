import { saucerSwapPoolAbi } from "./abi";
import { getAbiItem, toFunctionSelector } from "viem";
import { describe, expect, it } from "vitest";

describe("saucerSwapPoolAbi", () => {
  it("has the selectors the SaucerSwapPool facet exports", () => {
    const selector = (name: "seedPool" | "poolInfo" | "transferLiquidity") =>
      toFunctionSelector(getAbiItem({ abi: saucerSwapPoolAbi, name }));
    expect(selector("seedPool")).toBe("0x55650bd1");
    expect(selector("poolInfo")).toBe("0x5a2f3d09");
    expect(selector("transferLiquidity")).toBe("0x001cf43d");
  });
});
