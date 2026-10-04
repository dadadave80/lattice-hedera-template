import { Abi, Hex, toFunctionSelector } from "viem";

/** A Lattice diamond routes a plain HBAR transfer through this selector, to its Receive facet. */
const RECEIVE_SELECTOR = "0x00000000";

/** Maps every function selector found in `abis` to the function's name, for showing a diamond's routes. */
export function selectorNames(abis: Abi[]): Map<Hex, string> {
  const names = new Map<Hex, string>([[RECEIVE_SELECTOR, "receive"]]);
  for (const abi of abis) {
    for (const item of abi) {
      if (item.type === "function") names.set(toFunctionSelector(item), item.name);
    }
  }
  return names;
}
