import { ContractFunctionReturnType, parseAbi } from "viem";

/**
 * `ISaucerSwapPool`. A diamond deployed before the facet existed gains it by a cut, so the generated `Diamond` ABI may
 * not list it. The errors are here so a failed simulation names them.
 */
export const saucerSwapPoolAbi = parseAbi([
  "struct PoolInfo { address router; address factory; address whbar; address pair; address lpToken; uint256 lpBalance; uint256 lpTotalSupply; uint256 reserveTokens; uint256 reserveTinybars; uint256 creationFee; }",
  "function seedPool(int64 tokens, uint256 tinybars, int64 minTokens, uint256 minTinybars, uint256 maxCreationFee, uint256 deadline) payable returns (int64 tokensAdded, uint256 tinybarsAdded, uint256 liquidity)",
  "function transferLiquidity(address to, int64 amount)",
  "function poolInfo() view returns (PoolInfo info)",
  "event PoolSeeded(address indexed pair, address indexed lpToken, bool created, int64 tokens, uint256 tinybars, uint256 liquidity, uint256 creationFee)",
  "event LiquidityTransferred(address indexed lpToken, address indexed to, int64 amount)",
  "error SaucerSwapPoolNotConfigured()",
  "error SaucerSwapPoolInvalidAmount()",
  "error SaucerSwapPoolInsufficientHbar(uint256 needed, uint256 balance)",
  "error SaucerSwapPoolInsufficientTokens(uint256 needed, uint256 balance)",
  "error SaucerSwapPoolCreationFeeTooHigh(uint256 fee, uint256 maxCreationFee)",
  "error SaucerSwapPoolApproveFailed(int64 responseCode)",
  "error SaucerSwapPoolAssociateFailed(int64 responseCode)",
  "error SaucerSwapPoolNoLiquidity()",
  "error SaucerSwapPoolTransferFailed(int64 responseCode)",
]);

/** What `poolInfo()` returns. */
export type PoolInfo = ContractFunctionReturnType<typeof saucerSwapPoolAbi, "view", "poolInfo">;
