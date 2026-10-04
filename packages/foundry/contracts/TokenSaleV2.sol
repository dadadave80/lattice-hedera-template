// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TokenSale } from "./TokenSale.sol";

/// @title TokenSaleV2
/// @notice The upgrade used in the README walkthrough: the same sale with a 5% early-bird bonus. Cutting it
///         into a live diamond replaces TokenSale's selectors and adds `bonusBps()`. The token, the price,
///         the totals and the diamond's address are untouched, because all of that lives in the diamond.
/// @dev The bonus also prices stealth purchases, which read the diamond's `quote`. `bonusBps()` is not in the
///      app's generated `Diamond` ABI, because a full deploy cuts `TokenSale`; read it with an inline ABI.
contract TokenSaleV2 is TokenSale {
    /// @dev 500 bps = 5% more token units per payment.
    uint256 internal constant BONUS_BPS = 500;

    /// @notice The bonus added to every quote and purchase.
    /// @return The bonus in basis points (10,000 = 100%).
    function bonusBps() external pure virtual returns (uint256) {
        return BONUS_BPS;
    }

    function _bonusBps() internal pure virtual override returns (uint256) {
        return BONUS_BPS;
    }

    /// @notice ERC-8153: TokenSale's selectors, then `bonusBps()` 0x404f21a5.
    /// @dev `test/TokenSaleUpgrade.t.sol` checks this list against the ABI.
    /// @return selectors The selectors, concatenated.
    function exportSelectors() external pure virtual override returns (bytes memory selectors) {
        selectors = hex"08bf598ddf1d74aeed1bd76c8e3695b81919fed7970ea83e404f21a5";
    }
}
