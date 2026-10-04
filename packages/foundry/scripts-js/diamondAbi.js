// A Lattice diamond is many facets behind one address. These helpers turn the deploy script's record of
// that diamond into what the frontend wants: a single contract with a single ABI.

/** Contracts a Lattice deploy creates along the way that the app never calls. */
const DEPLOY_PLUMBING = new Set([
  "LatticeRegistry",
  "LatticeFactory",
  "MultiInit",
]);

/**
 * True for a contract the frontend should not list on its own: deploy plumbing, an initializer,
 * or a facet that is already reachable through the diamond.
 */
export function isPlumbing(contractName, facetNames) {
  return (
    DEPLOY_PLUMBING.has(contractName) ||
    contractName.endsWith("Init") ||
    facetNames.includes(contractName)
  );
}

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

/**
 * Forge writes a contract's artifact to `out/<file>.sol/<contract>.json`, and `generateTsAbis.js` looks it up by
 * the contract's name alone, so a facet in a file named otherwise is not found.
 */
function facetArtifact(name, artifactOf) {
  let artifact;
  try {
    artifact = artifactOf(name);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  if (!artifact) {
    throw new Error(
      `The diamond record lists the facet ${name}, but out/${name}.sol/${name}.json does not exist. ` +
        `Put ${name} in contracts/${name}.sol, a file named after it, run forge build, then node scripts-js/generateTsAbis.js.`
    );
  }
  return artifact;
}

/**
 * A chain's contracts as the frontend should see them: one `Diamond`, followed by whatever was deployed
 * on its own (an upgrade facet waiting to be cut in, for example).
 *
 * @param contracts what the broadcast files list for the chain, keyed by contract name
 * @param record the deploy script's `deployments/diamond/<chainId>.json`
 * @param artifactOf returns a contract's Forge artifact by name
 */
export function withDiamond(contracts, record, artifactOf) {
  const facets = record.facets.map((name) => {
    const { abi, methodIdentifiers } = facetArtifact(name, artifactOf);
    return { abi, methodIdentifiers, selectors: record.selectors[name] };
  });
  const standalone = Object.entries(contracts).filter(
    ([name]) => !isPlumbing(name, record.facets)
  );
  return {
    Diamond: {
      address: record.address,
      abi: mergeDiamondAbi(facets),
      inheritedFunctions: {},
      deployedOnBlock: record.deployedOnBlock,
    },
    ...Object.fromEntries(standalone),
  };
}
