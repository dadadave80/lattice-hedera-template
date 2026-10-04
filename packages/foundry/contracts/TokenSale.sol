// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ITokenSale } from "./interfaces/ITokenSale.sol";
import { TokenSaleLib, TokenSaleStorage } from "./libraries/TokenSaleLib.sol";

/// @title TokenSale
/// @notice Diamond facet that sells the diamond's own HTS token for HBAR at a USD price.
/// @dev Stateless: every function forwards to TokenSaleLib. Cut it into a diamond that also carries
///      `HTSAdapter`, `AccessControl` and a price-feed facet such as `ChainlinkAdapter`.
contract TokenSale is ITokenSale {
    /// @inheritdoc ITokenSale
    function launchSale(
        string calldata name,
        string calldata symbol,
        string calldata memo,
        int32 decimals,
        int64 supply,
        uint256 priceUsd
    ) external payable virtual returns (address token) {
        return TokenSaleLib.launchSale(name, symbol, memo, decimals, supply, priceUsd);
    }

    /// @inheritdoc ITokenSale
    function quote(uint256 tinybars) external view virtual returns (int64 tokens) {
        return TokenSaleLib.quote(tinybars);
    }

    /// @inheritdoc ITokenSale
    function saleInfo()
        external
        view
        virtual
        returns (address token, int32 decimals, uint256 priceUsd, bytes32 feedKey, int64 sold, uint256 raised)
    {
        TokenSaleStorage storage $ = TokenSaleLib.tokenSaleStorage();
        return ($.token, $.decimals, $.priceUsd, $.feedKey, $.sold, $.raised);
    }

    /// @notice ERC-8153: the selectors this facet adds to a diamond, 4 bytes each.
    /// @dev Never includes `exportSelectors()` itself. `test/TokenSale.t.sol` checks this list against the ABI.
    ///      `launchSale(string,string,string,int32,int64,uint256)` 0xdf1d74ae
    ///      `quote(uint256)` 0xed1bd76c
    ///      `saleInfo()` 0x8e3695b8
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"df1d74aeed1bd76c8e3695b8";
    }
}
