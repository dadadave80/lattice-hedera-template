// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { SaucerSwapPoolLib } from "./libraries/SaucerSwapPoolLib.sol";

/// @title SaucerSwapPoolInit
/// @notice Initializer for the SaucerSwapPool facet. The diamond delegatecalls it once: while it is being created,
///         or through `UpgradeMultiInit` when the facet is cut into a diamond that already exists.
/// @dev The addresses differ between Hedera testnet and mainnet, so the deploy scripts pass them per chain.
contract SaucerSwapPoolInit {
    /// @param router SaucerSwapV1RouterV3.
    /// @param factory SaucerSwapV1Factory, the router's `factory()`.
    /// @param whbar The WHBAR HTS token, the router's `whbar()`. Not its `WHBAR()`, which is the wrapping contract.
    function init(address router, address factory, address whbar) external {
        SaucerSwapPoolLib.__SaucerSwapPool_init(router, factory, whbar);
    }
}
