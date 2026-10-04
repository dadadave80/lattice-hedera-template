import { SweepFeeClient, sweepFee } from "./sweepCost";
import { parseEther, parseGwei } from "viem";
import { describe, expect, it } from "vitest";

const TOKEN = "0x0000000000000000000000000000000000A59b36";
const STEALTH = "0x1210a841d5f6bf7e2af0f6037bc3f94b7478de24";
const NEW_ADDRESS = "0x7e3a9b2c4d5f6a7b8c9d0e1f2a3b4c5d6e7f8091";
const AMOUNT = 108_287_833n;

// `cast estimate` of this transfer on testnet: to an address with no account, and to an existing account.
const GAS_TO_NEW_ADDRESS = 783_066n;
const GAS_TO_EXISTING_ACCOUNT = 40_892n;
// The testnet base fee was 820 gwei; viem offers 1.2 times it.
const MAX_FEE_PER_GAS = parseGwei("984");

const fakeClient = (gas: bigint) => {
  const calls: unknown[] = [];
  const client = {
    estimateContractGas: async (parameters: unknown) => {
      calls.push(parameters);
      return gas;
    },
    estimateFeesPerGas: async () => ({ maxFeePerGas: MAX_FEE_PER_GAS, maxPriorityFeePerGas: 0n }),
  } as unknown as SweepFeeClient;
  return { client, calls };
};

describe("sweepFee", () => {
  it("estimates the token transfer as the stealth address sends it", async () => {
    const { client, calls } = fakeClient(GAS_TO_EXISTING_ACCOUNT);
    await sweepFee(client, { token: TOKEN, from: STEALTH, to: NEW_ADDRESS, amount: AMOUNT });
    expect(calls).toEqual([
      expect.objectContaining({
        account: STEALTH,
        address: TOKEN,
        functionName: "transfer",
        args: [NEW_ADDRESS, AMOUNT],
      }),
    ]);
  });

  it("is in weibars, the unit of the stealth address's balance over JSON-RPC", async () => {
    const { client } = fakeClient(GAS_TO_EXISTING_ACCOUNT);
    const fee = await sweepFee(client, { token: TOKEN, from: STEALTH, to: NEW_ADDRESS, amount: AMOUNT });
    expect(fee).toBe(GAS_TO_EXISTING_ACCOUNT * MAX_FEE_PER_GAS);
    expect(fee).toBeLessThan(parseEther("0.05"));
  });

  it("is more than a 0.5 HBAR stipend and less than 1 HBAR when the sweep creates the account", async () => {
    const { client } = fakeClient(GAS_TO_NEW_ADDRESS);
    const fee = await sweepFee(client, { token: TOKEN, from: STEALTH, to: NEW_ADDRESS, amount: AMOUNT });
    expect(fee).toBeGreaterThan(parseEther("0.5"));
    expect(fee).toBeLessThan(parseEther("1"));
  });
});
