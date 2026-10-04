import { Address } from "viem";

/**
 * The `0.0.N` id of a long-zero address, the form Hedera gives the tokens and contracts it creates natively. Undefined
 * for any other address, such as a SaucerSwap pair, which is deployed with CREATE2: ask the mirror node for its id.
 */
export function longZeroToEntityId(address: Address): string | undefined {
  if (!/^0x0{24}[0-9a-fA-F]{16}$/.test(address)) return undefined;
  return `0.0.${BigInt(`0x${address.slice(26)}`)}`;
}

/** SaucerSwap's app on the chain. */
export function saucerSwapUrl(chainId: number): string {
  return chainId === 295 ? "https://www.saucerswap.finance" : "https://testnet.saucerswap.finance";
}

/**
 * A pool's page on SaucerSwap, by the pair's contract id, e.g. `0.0.1461945`. SaucerSwap documents this path on
 * mainnet only; the testnet app is assumed to follow it.
 */
export function saucerSwapPoolUrl(chainId: number, pairContractId: string): string {
  return `${saucerSwapUrl(chainId)}/pool/${pairContractId}`;
}

/** HashScan's page for a contract or a token, by id or EVM address. */
export function hashScanUrl(chainId: number, kind: "contract" | "token", idOrAddress: string): string {
  return `https://hashscan.io/${chainId === 295 ? "mainnet" : "testnet"}/${kind}/${idOrAddress}`;
}
