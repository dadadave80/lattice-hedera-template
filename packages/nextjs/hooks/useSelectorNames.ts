import { useMemo } from "react";
import { Abi } from "viem";
import { useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { selectorNames } from "~~/utils/diamond/selectorNames";
import { GenericContract, contracts } from "~~/utils/scaffold-hbar/contract";

/** Selector to function name, from the ABI of every contract this project has deployed on the current network. */
export function useSelectorNames() {
  const { targetNetwork } = useTargetNetwork();

  return useMemo(() => {
    const deployed = (contracts?.[targetNetwork.id] ?? {}) as Record<string, GenericContract>;
    return selectorNames(Object.values(deployed).map(contract => contract.abi as Abi));
  }, [targetNetwork.id]);
}
