// A Lattice diamond is many facets behind one address. These helpers turn the deploy script's record of
// that diamond into what the frontend wants: a single contract with a single ABI.

function canonicalType(parameter) {
  if (!parameter.type.startsWith("tuple")) return parameter.type;
  const components = parameter.components.map(canonicalType).join(",");
  return `(${components})${parameter.type.slice("tuple".length)}`;
}

/** The signature Solidity hashes into a selector, e.g. `diamondCut((address,uint8,bytes4[])[],address,bytes)`. */
export function signatureOf(abiFunction) {
  return `${abiFunction.name}(${abiFunction.inputs
    .map(canonicalType)
    .join(",")})`;
}

/**
 * One ABI for the whole diamond: every function a facet actually serves, plus all events and errors.
 * A function a recipe excluded, or gave to another facet, is left out, and so is `exportSelectors()`,
 * because neither is among the facet's cut selectors.
 *
 * @param facets `{ abi, methodIdentifiers, selectors }` per facet, where `abi` and `methodIdentifiers`
 *   come from the facet's Forge artifact and `selectors` are the ones cut into the diamond.
 */
export function mergeDiamondAbi(facets) {
  const seen = new Set();
  const merged = [];
  for (const { abi, methodIdentifiers, selectors } of facets) {
    const served = new Set(selectors.map((selector) => selector.toLowerCase()));
    for (const entry of abi) {
      if (entry.type === "constructor") continue;
      if (entry.type === "function") {
        const selector = `0x${methodIdentifiers[signatureOf(entry)]}`;
        if (!served.has(selector)) continue;
      }
      const key = JSON.stringify(entry);
      if (seen.has(key)) continue;
      seen.add(key);
      merged.push(entry);
    }
  }
  return merged;
}
