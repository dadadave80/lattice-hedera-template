// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ISaucerSwapPool } from "./interfaces/ISaucerSwapPool.sol";
import { SaucerSwapPoolLib } from "./libraries/SaucerSwapPoolLib.sol";

/// @title SaucerSwapPool
/// @notice Diamond facet that puts the sale's token and HBAR into a SaucerSwap V1 pool and keeps the LP tokens.
/// @dev Stateless: it forwards to SaucerSwapPoolLib. Cut it into a diamond that also runs `TokenSale`, whose token
///      it pools, and `AccessControl` and `EmergencyStop`, which guard it. `SaucerSwapPoolInit` sets the addresses.
contract SaucerSwapPool is ISaucerSwapPool {
    /// @inheritdoc ISaucerSwapPool
    function seedPool(
        int64 tokens,
        uint256 tinybars,
        int64 minTokens,
        uint256 minTinybars,
        uint256 maxCreationFee,
        uint256 deadline
    ) external payable virtual returns (int64 tokensAdded, uint256 tinybarsAdded, uint256 liquidity) {
        return SaucerSwapPoolLib.seedPool(tokens, tinybars, minTokens, minTinybars, maxCreationFee, deadline);
    }

    /// @inheritdoc ISaucerSwapPool
    function poolInfo() external view virtual returns (PoolInfo memory info) {
        return SaucerSwapPoolLib.poolInfo();
    }

    /// @notice ERC-8153: the selectors this facet adds to a diamond, 4 bytes each.
    /// @dev Never includes `exportSelectors()` itself. `test/SaucerSwapPool.t.sol` checks this list against the ABI.
    ///      `seedPool(int64,uint256,int64,uint256,uint256,uint256)` 0x55650bd1
    ///      `poolInfo()` 0x5a2f3d09
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"55650bd15a2f3d09";
    }
}
