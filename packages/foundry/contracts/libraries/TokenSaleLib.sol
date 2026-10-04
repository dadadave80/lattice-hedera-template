// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { AccessControlLib, DEFAULT_ADMIN_ROLE } from "@lattice/access/libraries/AccessControlLib.sol";
import { HederaResponseCodes } from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import { IHederaTokenService } from "@lattice/interfaces/external/hedera/IHederaTokenService.sol";
import { EmergencyStopLib } from "@lattice/security/libraries/EmergencyStopLib.sol";
import { HTSAdapterLib, HTS_SYSTEM_CONTRACT } from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import { InitializableLib } from "@lattice/utils/libraries/InitializableLib.sol";
import { ITokenSale } from "../interfaces/ITokenSale.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice-hedera-template.storage.TokenSale")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant TOKEN_SALE_STORAGE_SLOT = 0x6e569de6c6a1948b3edf921eb24b1102436ae1d4a44d5296089020d12a122800;

/// @dev Tinybars in one HBAR.
uint256 constant TINYBARS_PER_HBAR = 1e8;

/// @dev Basis points in 100%.
uint256 constant BPS = 10_000;

/// @dev The largest amount an HTS `int64` can carry: `type(int64).max`.
uint256 constant MAX_TOKEN_UNITS = 9_223_372_036_854_775_807;

/// @notice ERC-7201 namespaced storage for TokenSale, shared by every sale facet and StealthBuy. Append new
///         fields at the end; never reorder or remove one.
/// @custom:storage-location erc7201:lattice-hedera-template.storage.TokenSale
struct TokenSaleStorage {
    /// The HTS token on sale; zero until `launchSale`.
    address token;
    /// The token's decimals, 0..18.
    int32 decimals;
    /// Token units sold, by `buy` and `buyFor` alike.
    int64 sold;
    /// The key passed to the diamond's `latestAnswer(bytes32)`, set once by `TokenSaleInit`.
    bytes32 feedKey;
    /// USD per whole token, 18 decimals.
    uint256 priceUsd;
    /// Tinybars paid for tokens, stipends excluded. Withdrawals do not reduce it.
    uint256 raised;
}

/// @title IPriceFeed
/// @notice The read every Lattice price-feed facet serves under the same selector.
interface IPriceFeed {
    /// @notice The latest price for `key`.
    /// @param key The feed's key, such as `"HBAR/USD"`.
    /// @return answerWad The price, 18 decimals. Lattice's adapters revert when the answer is older than the
    ///         feed's registered staleness limit.
    function latestAnswer(bytes32 key) external view returns (int256 answerWad);
}

/// @title TokenSaleLib
/// @notice Logic and storage for the TokenSale facet. The facet is a stateless forwarder, which is the Lattice
///         module pattern: an upgrade swaps the facet while this storage stays where it is.
/// @dev Runs in the diamond's context: `address(this)` is the diamond, which holds the HBAR, treasuries the
///      token and serves the oracle read. HBAR amounts are tinybars, USD amounts 18-decimal fixed point.
library TokenSaleLib {
    /// @notice The sale's storage, at its ERC-7201 slot in the diamond.
    /// @return $ The storage pointer.
    function tokenSaleStorage() internal pure returns (TokenSaleStorage storage $) {
        assembly {
            $.slot := TOKEN_SALE_STORAGE_SLOT
        }
    }

    /// @notice Stores the oracle feed key. Runs once, inside the diamond's initializing window.
    /// @dev Reverts with `NotInitializing` outside that window.
    /// @param feedKey The key passed to the diamond's `latestAnswer(bytes32)`.
    function __TokenSale_init(bytes32 feedKey) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        tokenSaleStorage().feedKey = feedKey;
    }

    /// @notice See `ITokenSale.launchSale`. Checks `DEFAULT_ADMIN_ROLE` here; `HTSAdapterLib` checks
    ///         `HTS_MANAGER_ROLE` and forwards `msg.value` to HTS as the creation fee.
    /// @dev HTS failures surface as `HTSAdapterLib`'s errors, and a negative `supply` as `HTSInvalidAmount`.
    /// @param name The token's name.
    /// @param symbol The token's symbol.
    /// @param memo The token's memo.
    /// @param decimals Token decimals, 0..18.
    /// @param supply Initial supply in token units, minted to the diamond.
    /// @param priceUsd USD per whole token, 18 decimals.
    /// @return token The new token's address.
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

    /// @notice See `ITokenSale.setSalePrice`. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param priceUsd USD per whole token, 18 decimals; not zero.
    function setSalePrice(uint256 priceUsd) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (priceUsd == 0) revert ITokenSale.TokenSaleInvalidPrice();
        tokenSaleStorage().priceUsd = priceUsd;
        emit ITokenSale.SalePriceSet(priceUsd);
    }

    /// @notice See `ITokenSale.withdrawProceeds`. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @dev Emits before the transfer, and the recipient's code runs with all the gas the call forwards. Not
    ///      gated by the emergency stop.
    /// @param to The recipient.
    /// @param tinybars The amount to send.
    function withdrawProceeds(address payable to, uint256 tinybars) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        emit ITokenSale.ProceedsWithdrawn(to, tinybars);
        (bool ok,) = to.call{ value: tinybars }("");
        if (!ok) revert ITokenSale.TokenSaleWithdrawFailed();
    }

    /// @notice See `ITokenSale.buy`. Prices the whole `msg.value`; the remainder that buys less than one unit
    ///         stays in the diamond and is counted in `raised`.
    /// @dev Checks the emergency stop first, so a stopped sale reverts with `EmergencyStopActive` even before
    ///      launch. Books the totals and emits before the HTS transfer, which reverts the whole purchase if it
    ///      fails (`TokenSaleTransferFailed(178)` when sold out).
    /// @param minTokens The fewest token units the payment may buy.
    /// @param bonusBps Extra tokens on top of the quote, in basis points. The facet decides it.
    /// @return tokens Token units transferred to the caller.
    function buy(int64 minTokens, uint256 bonusBps) internal returns (int64 tokens) {
        EmergencyStopLib.checkNotStopped();
        TokenSaleStorage storage $ = tokenSaleStorage();
        uint256 hbarUsd = _hbarUsd($);
        tokens = _tokensFor($, msg.value, hbarUsd, bonusBps);
        if (tokens < minTokens) revert ITokenSale.TokenSaleSlippage(tokens, minTokens);

        $.sold += tokens;
        $.raised += msg.value;
        emit ITokenSale.TokensPurchased(msg.sender, msg.value, tokens, hbarUsd);
        _transferFromTreasury($.token, msg.sender, tokens);
    }

    /// @notice See `ITokenSale.quote`.
    /// @param tinybars The payment to price.
    /// @param bonusBps Extra tokens on top of the quote, in basis points.
    /// @return tokens Token units the payment buys, rounded down.
    function quote(uint256 tinybars, uint256 bonusBps) internal view returns (int64 tokens) {
        TokenSaleStorage storage $ = tokenSaleStorage();
        return _tokensFor($, tinybars, _hbarUsd($), bonusBps);
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

    /// @dev units = tinybars * (USD per HBAR) * 10^decimals * (1 + bonus) / (tinybars per HBAR * USD per token).
    ///      One division, so nothing is rounded away before the bonus is applied. `decimals` is 0..18 and the
    ///      result is range-checked, which is what makes the casts safe.
    function _tokensFor(TokenSaleStorage storage $, uint256 tinybars, uint256 hbarUsd, uint256 bonusBps)
        private
        view
        returns (int64)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 unit = 10 ** uint256(uint32($.decimals));
        uint256 units = (tinybars * hbarUsd * unit * (BPS + bonusBps)) / (TINYBARS_PER_HBAR * $.priceUsd * BPS);
        if (units == 0 || units > MAX_TOKEN_UNITS) revert ITokenSale.TokenSaleInvalidAmount();
        // forge-lint: disable-next-line(unsafe-typecast)
        return int64(uint64(units));
    }

    /// @dev HTS returns a response code instead of reverting, so the code is checked here. The call is a plain
    ///      `call` from the diamond: HTS sees the diamond as sender, and the diamond holds the tokens. Internal
    ///      for `StealthBuyLib`, which pays out the same way.
    ///      184 (`TOKEN_NOT_ASSOCIATED_TO_ACCOUNT`) reverts with `TokenSaleBuyerNotAssociated(to)`. A failed call
    ///      frame counts as 21 (`UNKNOWN`). Any other code but 22 (`SUCCESS`) reverts with
    ///      `TokenSaleTransferFailed(code)`, 178 (`INSUFFICIENT_TOKEN_BALANCE`) among them when the sale is sold out.
    /// @param token The HTS token.
    /// @param to The recipient.
    /// @param tokens Token units to send.
    function _transferFromTreasury(address token, address to, int64 tokens) internal {
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
