// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { AccessControlLib, DEFAULT_ADMIN_ROLE } from "@lattice/access/libraries/AccessControlLib.sol";
import { HederaResponseCodes } from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import { IHederaTokenService } from "@lattice/interfaces/external/hedera/IHederaTokenService.sol";
import { HTSAdapterLib, HTS_SYSTEM_CONTRACT } from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import { InitializableLib } from "@lattice/utils/libraries/InitializableLib.sol";
import { ITokenSale } from "../interfaces/ITokenSale.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice-hedera-template.storage.TokenSale")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant TOKEN_SALE_STORAGE_SLOT = 0x6e569de6c6a1948b3edf921eb24b1102436ae1d4a44d5296089020d12a122800;

/// @dev Tinybars in one HBAR.
uint256 constant TINYBARS_PER_HBAR = 1e8;

/// @dev The largest amount an HTS `int64` can carry.
uint256 constant MAX_TOKEN_UNITS = 9_223_372_036_854_775_807;

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

/// @notice The read every Lattice price-feed facet serves under the same selector.
interface IPriceFeed {
    function latestAnswer(bytes32 key) external view returns (int256 answerWad);
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

    function buy(int64 minTokens) internal returns (int64 tokens) {
        TokenSaleStorage storage $ = tokenSaleStorage();
        uint256 hbarUsd = _hbarUsd($);
        tokens = _tokensFor($, msg.value, hbarUsd);
        if (tokens < minTokens) revert ITokenSale.TokenSaleSlippage(tokens, minTokens);

        $.sold += tokens;
        $.raised += msg.value;
        emit ITokenSale.TokensPurchased(msg.sender, msg.value, tokens, hbarUsd);
        _transferFromTreasury($.token, msg.sender, tokens);
    }

    function quote(uint256 tinybars) internal view returns (int64 tokens) {
        TokenSaleStorage storage $ = tokenSaleStorage();
        return _tokensFor($, tinybars, _hbarUsd($));
    }

    /// @dev USD per HBAR, 18 decimals, read through the diamond's own `latestAnswer(bytes32)` selector rather
    ///      than from a specific adapter library. That is what lets a recipe swap the oracle facet without
    ///      touching this one.
    function _hbarUsd(TokenSaleStorage storage $) private view returns (uint256) {
        if ($.token == address(0)) revert ITokenSale.TokenSaleNotLaunched();
        int256 answer = IPriceFeed(address(this)).latestAnswer($.feedKey);
        if (answer <= 0) revert ITokenSale.TokenSaleInvalidPrice();
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(answer);
    }

    /// @dev units = tinybars * (USD per HBAR) * 10^decimals / (tinybars per HBAR * USD per token).
    ///      One division, so nothing is rounded away early. `decimals` is 0..18 and the result is
    ///      range-checked, which is what makes the casts safe.
    function _tokensFor(TokenSaleStorage storage $, uint256 tinybars, uint256 hbarUsd) private view returns (int64) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 unit = 10 ** uint256(uint32($.decimals));
        uint256 units = (tinybars * hbarUsd * unit) / (TINYBARS_PER_HBAR * $.priceUsd);
        if (units == 0 || units > MAX_TOKEN_UNITS) revert ITokenSale.TokenSaleInvalidAmount();
        // forge-lint: disable-next-line(unsafe-typecast)
        return int64(uint64(units));
    }

    /// @dev HTS returns a response code instead of reverting, so the code is checked here. The call is a plain
    ///      `call` from the diamond: HTS sees the diamond as sender, and the diamond holds the tokens.
    function _transferFromTreasury(address token, address to, int64 tokens) private {
        (bool ok, bytes memory ret) = HTS_SYSTEM_CONTRACT.call(
            abi.encodeCall(IHederaTokenService.transferToken, (token, address(this), to, tokens))
        );
        int64 code = ok ? abi.decode(ret, (int64)) : HederaResponseCodes.UNKNOWN;
        if (code == HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT) {
            revert ITokenSale.TokenSaleBuyerNotAssociated(to);
        }
        if (code != HederaResponseCodes.SUCCESS) revert ITokenSale.TokenSaleTransferFailed(code);
    }
}
