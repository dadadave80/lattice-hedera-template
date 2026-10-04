import { Address, zeroAddress } from "viem";
import { useScaffoldReadContract } from "~~/hooks/scaffold-hbar";

/** The sale's on-chain configuration and totals, read from the diamond's `saleInfo()`. */
export function useSale() {
  const { data, isLoading } = useScaffoldReadContract({ contractName: "Diamond", functionName: "saleInfo" });
  const [token, decimals, priceUsd, feedKey, sold, raised] = data ?? [];

  return {
    isLoading,
    /** False until the admin has called `launchSale`. */
    isLaunched: token !== undefined && token !== zeroAddress,
    token: token as Address | undefined,
    decimals: decimals ?? 0,
    priceUsd: priceUsd ?? 0n,
    feedKey,
    sold: sold ?? 0n,
    raised: raised ?? 0n,
  };
}
