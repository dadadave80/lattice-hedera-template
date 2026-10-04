import { Address, PublicClient, erc20Abi } from "viem";

export type SweepFeeClient = Pick<PublicClient, "estimateContractGas" | "estimateFeesPerGas">;

/**
 * The HBAR, in weibars, a stealth address must hold to send its sweep of `amount` tokens to `to`. viem sends the gas
 * estimate as the limit and offers 1.2 times the base fee, and the relay turns a transaction away unless its sender
 * holds the limit's worth at that fee. Hedera then charges the gas used at the network price, which is less.
 * A sweep to an address with no Hedera account creates the account (HIP-583), which costs about 19 times as much as a
 * sweep to an existing account.
 */
export async function sweepFee(
  client: SweepFeeClient,
  { token, from, to, amount }: { token: Address; from: Address; to: Address; amount: bigint },
): Promise<bigint> {
  const [gas, { maxFeePerGas }] = await Promise.all([
    client.estimateContractGas({
      account: from,
      address: token,
      abi: erc20Abi,
      functionName: "transfer",
      args: [to, amount],
    }),
    client.estimateFeesPerGas(),
  ]);
  return gas * maxFeePerGas;
}
