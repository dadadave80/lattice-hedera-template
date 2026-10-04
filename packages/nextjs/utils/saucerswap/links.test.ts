import { hashScanUrl, longZeroToEntityId, saucerSwapPoolUrl, saucerSwapUrl } from "./links";
import { describe, expect, it } from "vitest";

describe("longZeroToEntityId", () => {
  it("reads the entity number out of a long-zero address", () => {
    expect(longZeroToEntityId("0x0000000000000000000000000000000000003aD2")).toBe("0.0.15058");
  });

  it("is undefined for an address that is not long-zero", () => {
    expect(longZeroToEntityId("0x4Eb94355872aB90ab258B940eE98B706dC9B2aa9")).toBeUndefined();
  });
});

describe("saucerSwap links", () => {
  it("picks the mainnet or testnet app by chain", () => {
    expect(saucerSwapUrl(295)).toBe("https://www.saucerswap.finance");
    expect(saucerSwapUrl(296)).toBe("https://testnet.saucerswap.finance");
  });

  it("links a pool by its pair's contract id", () => {
    expect(saucerSwapPoolUrl(295, "0.0.1461945")).toBe("https://www.saucerswap.finance/pool/0.0.1461945");
  });
});

describe("hashScanUrl", () => {
  it("links a contract or a token on the chain's HashScan", () => {
    expect(hashScanUrl(296, "token", "0.0.15058")).toBe("https://hashscan.io/testnet/token/0.0.15058");
    expect(hashScanUrl(295, "contract", "0x1")).toBe("https://hashscan.io/mainnet/contract/0x1");
  });
});
