// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { AccessControlLib, DEFAULT_ADMIN_ROLE } from "@lattice/access/libraries/AccessControlLib.sol";
import { HTSAdapterLib } from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import { InitializableLib } from "@lattice/utils/libraries/InitializableLib.sol";
import { ITokenSale } from "../interfaces/ITokenSale.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice-hedera-template.storage.TokenSale")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant TOKEN_SALE_STORAGE_SLOT = 0x6e569de6c6a1948b3edf921eb24b1102436ae1d4a44d5296089020d12a122800;

/// @notice ERC-7201 namespaced storage for TokenSale. Append new fields at the end; never reorder.
/// @custom:storage-location erc7201:lattice-hedera-template.storage.TokenSale
struct TokenSaleStorage {
    address token;
    int32 decimals;
    int64 sold;
    bytes32 feedKey;
    uint256 priceUsd;
    uint256 raised;
}

/// @title TokenSaleLib
/// @notice Logic and storage for the TokenSale facet. The facet is a stateless forwarder, which is the Lattice
///         module pattern: an upgrade swaps the facet while this storage stays where it is.
library TokenSaleLib {
    function tokenSaleStorage() internal pure returns (TokenSaleStorage storage $) {
        assembly {
            $.slot := TOKEN_SALE_STORAGE_SLOT
        }
    }

    /// @notice Stores the oracle feed key. Runs once, inside the diamond's initializing window.
    function __TokenSale_init(bytes32 feedKey) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        tokenSaleStorage().feedKey = feedKey;
    }

    function launchSale(
        string calldata name,
        string calldata symbol,
        string calldata memo,
        int32 decimals,
        int64 supply,
        uint256 priceUsd
    ) internal returns (address token) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        TokenSaleStorage storage $ = tokenSaleStorage();
        if ($.token != address(0)) revert ITokenSale.TokenSaleAlreadyLaunched($.token);
        if (priceUsd == 0) revert ITokenSale.TokenSaleInvalidPrice();
        if (decimals < 0 || decimals > 18) revert ITokenSale.TokenSaleInvalidDecimals(decimals);

        // The diamond becomes the token's treasury and holds its admin and supply keys. Max supply 0 means
        // the supply is not capped, so `HTSAdapter.mintToken` can restock the sale.
        token = HTSAdapterLib.createFungibleToken(name, symbol, memo, decimals, supply, 0);
        $.token = token;
        $.decimals = decimals;
        $.priceUsd = priceUsd;
        emit ITokenSale.SaleLaunched(token, decimals, supply, priceUsd);
    }
}
