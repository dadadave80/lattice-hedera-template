import { useEffect } from "react";
import { Address } from "viem";
import { useBalance, useBlockNumber } from "wagmi";
import { useTargetNetwork } from "~~/hooks/scaffold-hbar";

/** An address's HBAR balance, read again at every block, so funding the wallet shows without a reload. */
export const useWatchedBalance = (address?: Address) => {
  const { targetNetwork } = useTargetNetwork();
  const balance = useBalance({ address, chainId: targetNetwork.id, query: { enabled: address !== undefined } });
  const { data: blockNumber } = useBlockNumber({ watch: true, chainId: targetNetwork.id });

  useEffect(() => {
    if (address) balance.refetch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [blockNumber]);

  return balance;
};
