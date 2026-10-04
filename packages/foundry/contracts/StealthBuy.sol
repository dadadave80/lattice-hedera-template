// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IStealthBuy } from "./interfaces/IStealthBuy.sol";
import { StealthBuyLib } from "./libraries/StealthBuyLib.sol";

/// @title StealthBuy
/// @notice Diamond facet that buys the sale's token for a recipient's one-time ERC-5564 stealth address.
/// @dev Stateless: it forwards to StealthBuyLib. Cut it into a diamond that also runs `TokenSale` (or an
///      upgrade of it), whose quote, totals and treasury it uses. Recipients publish their stealth meta-address
///      with `ERC6538Registry`, and wallets scan for deliveries in the diamond's ERC-5564 `Announcement` logs.
contract StealthBuy is IStealthBuy {
    /// @inheritdoc IStealthBuy
    function buyFor(
        address stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes1 viewTag,
        int64 minTokensOut,
        uint256 stipend
    ) external payable virtual returns (int64 tokens) {
        return StealthBuyLib.buyFor(stealthAddress, ephemeralPubKey, viewTag, minTokensOut, stipend);
    }

    /// @notice ERC-8153: the selectors this facet adds to a diamond, 4 bytes each.
    /// @dev Never includes `exportSelectors()` itself. `test/StealthBuy.t.sol` checks this list against the ABI.
    ///      `buyFor(address,bytes,bytes1,int64,uint256)` 0x80b0a3b4
    /// @return selectors The selectors, concatenated.
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"80b0a3b4";
    }
}
