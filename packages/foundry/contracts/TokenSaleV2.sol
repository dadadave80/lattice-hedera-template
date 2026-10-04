// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TokenSale } from "./TokenSale.sol";

/// @title TokenSaleV2
/// @notice The upgrade used in the README walkthrough: the same sale with a 5% early-bird bonus. Cutting it
///         into a live diamond replaces TokenSale's selectors and adds `bonusBps()`. The token, the price,
///         the totals and the diamond's address are untouched, because all of that lives in the diamond.
contract TokenSaleV2 is TokenSale {
    uint256 internal constant BONUS_BPS = 500;

    /// @notice The bonus added to every quote and purchase, in basis points.
    function bonusBps() external pure virtual returns (uint256) {
        return BONUS_BPS;
    }

    function _bonusBps() internal pure virtual override returns (uint256) {
        return BONUS_BPS;
    }

    /// @notice ERC-8153: TokenSale's selectors, then `bonusBps()` 0x404f21a5.
    function exportSelectors() external pure virtual override returns (bytes memory selectors) {
        selectors = hex"08bf598ddf1d74aeed1bd76c8e3695b81919fed7970ea83e404f21a5";
    }
}
