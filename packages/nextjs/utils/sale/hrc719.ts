/**
 * HIP-719: every HTS token address answers these calls for the account that makes them, so a wallet can
 * associate itself with a token through an ordinary contract call.
 */
export const hrc719Abi = [
  {
    type: "function",
    name: "associate",
    inputs: [],
    outputs: [{ name: "responseCode", type: "uint256" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "isAssociated",
    inputs: [],
    outputs: [{ name: "associated", type: "bool" }],
    stateMutability: "view",
  },
] as const;
