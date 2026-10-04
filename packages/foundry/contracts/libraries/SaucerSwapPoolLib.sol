// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { AccessControlLib, DEFAULT_ADMIN_ROLE } from "@lattice/access/libraries/AccessControlLib.sol";
import { HederaResponseCodes } from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import { IHRC719 } from "@lattice/interfaces/external/hedera/IHRC719.sol";
import { IHederaTokenService } from "@lattice/interfaces/external/hedera/IHederaTokenService.sol";
import { IERC20 } from "@lattice/interfaces/tokens/IERC20.sol";
import { HederaExchangeRateAdapterLib } from "@lattice/oracles/hedera/HederaExchangeRateAdapterLib.sol";
import { EmergencyStopLib } from "@lattice/security/libraries/EmergencyStopLib.sol";
import { HTS_SYSTEM_CONTRACT } from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import { InitializableLib } from "@lattice/utils/libraries/InitializableLib.sol";
import { ISaucerSwapPool } from "../interfaces/ISaucerSwapPool.sol";
import {
    IHederaTokenServiceApprove,
    ISaucerSwapV1Factory,
    ISaucerSwapV1Pair,
    ISaucerSwapV1Router
} from "../interfaces/ISaucerSwapV1.sol";
import { ITokenSale } from "../interfaces/ITokenSale.sol";
import { TokenSaleLib } from "./TokenSaleLib.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice-hedera-template.storage.SaucerSwapPool")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant SAUCERSWAP_POOL_STORAGE_SLOT = 0x0be13bbe52fde959265aa1b3244cb8dc1aa6979c161440fd094649e3309bd500;

/// @notice ERC-7201 namespaced storage for SaucerSwapPool. Append new fields at the end; never reorder.
/// @custom:storage-location erc7201:lattice-hedera-template.storage.SaucerSwapPool
struct SaucerSwapPoolStorage {
    /// @dev SaucerSwapV1RouterV3, set once by `SaucerSwapPoolInit`.
    address router;
    /// @dev SaucerSwapV1Factory, set once by `SaucerSwapPoolInit`.
    address factory;
    /// @dev The WHBAR HTS token (the router's `whbar()`, not its `WHBAR()` contract), set by `SaucerSwapPoolInit`.
    address whbar;
    /// @dev The pair the diamond last added liquidity to.
    address pair;
    /// @dev That pair's LP token.
    address lpToken;
}

/// @title SaucerSwapPoolLib
/// @notice Logic and storage for the SaucerSwapPool facet. It reads the sale's token from `TokenSaleStorage` and
///         adds liquidity from the diamond, which is the token's treasury and holds the sale's HBAR.
library SaucerSwapPoolLib {
    /// @notice The facet's storage, at its ERC-7201 slot.
    function saucerSwapPoolStorage() internal pure returns (SaucerSwapPoolStorage storage $) {
        assembly {
            $.slot := SAUCERSWAP_POOL_STORAGE_SLOT
        }
    }

    /// @notice Stores the SaucerSwap addresses. Runs inside an initializing window: the diamond's creation, or the
    ///         reinitializer `UpgradeMultiInit` opens when the facet is cut into an existing diamond.
    function __SaucerSwapPool_init(address router, address factory, address whbar) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (router == address(0) || factory == address(0) || whbar == address(0)) {
            revert ISaucerSwapPool.SaucerSwapPoolNotConfigured();
        }
        SaucerSwapPoolStorage storage $ = saucerSwapPoolStorage();
        $.router = router;
        $.factory = factory;
        $.whbar = whbar;
    }

    /// @dev One `seedPool` call's amounts, kept in memory because they do not fit on the stack.
    struct Seed {
        address token;
        address pair;
        bool created;
        uint256 units;
        uint256 tinybars;
        uint256 fee;
        uint256 minTokens;
        uint256 minTinybars;
        uint256 deadline;
    }

    /// @notice See `ISaucerSwapPool.seedPool`.
    function seedPool(
        int64 tokens,
        uint256 tinybars,
        int64 minTokens,
        uint256 minTinybars,
        uint256 maxCreationFee,
        uint256 deadline
    ) internal returns (int64 tokensAdded, uint256 tinybarsAdded, uint256 liquidity) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        EmergencyStopLib.checkNotStopped();
        SaucerSwapPoolStorage storage $ = saucerSwapPoolStorage();
        if ($.router == address(0)) revert ISaucerSwapPool.SaucerSwapPoolNotConfigured();
        Seed memory seed;
        seed.token = TokenSaleLib.tokenSaleStorage().token;
        if (seed.token == address(0)) revert ITokenSale.TokenSaleNotLaunched();
        // The minimums are required even when no pool exists: if someone creates the pool before this transaction
        // lands, the call adds to their pool at their price, and only the minimums stop it.
        if (tokens <= 0 || tinybars == 0 || minTokens <= 0 || minTinybars == 0) {
            revert ISaucerSwapPool.SaucerSwapPoolInvalidAmount();
        }
        // Both are positive `int64`s, checked above.
        // forge-lint: disable-next-line(unsafe-typecast)
        seed.units = uint256(uint64(tokens));
        // forge-lint: disable-next-line(unsafe-typecast)
        seed.minTokens = uint256(uint64(minTokens));
        seed.tinybars = tinybars;
        seed.minTinybars = minTinybars;
        seed.deadline = deadline;

        seed.pair = ISaucerSwapV1Factory($.factory).getPair(seed.token, $.whbar);
        seed.created = seed.pair == address(0);
        if (seed.created) {
            seed.fee = creationFee($);
            if (seed.fee > maxCreationFee) {
                revert ISaucerSwapPool.SaucerSwapPoolCreationFeeTooHigh(seed.fee, maxCreationFee);
            }
        } else {
            _associate(ISaucerSwapV1Pair(seed.pair).lpToken());
        }
        _requireFunds(seed.token, seed.units, seed.tinybars + seed.fee);

        uint256 tokensTaken;
        (tokensTaken, tinybarsAdded, liquidity) = _addLiquidity($, seed);
        // The router never takes more than `units`, which came from an `int64`.
        // forge-lint: disable-next-line(unsafe-typecast)
        tokensAdded = int64(uint64(tokensTaken));

        if (seed.created) seed.pair = ISaucerSwapV1Factory($.factory).getPair(seed.token, $.whbar);
        address lp = ISaucerSwapV1Pair(seed.pair).lpToken();
        $.pair = seed.pair;
        $.lpToken = lp;
        emit ISaucerSwapPool.PoolSeeded(seed.pair, lp, seed.created, tokensAdded, tinybarsAdded, liquidity, seed.fee);
    }

    /// @notice See `ISaucerSwapPool.transferLiquidity`.
    function transferLiquidity(address to, int64 amount) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (amount <= 0) revert ISaucerSwapPool.SaucerSwapPoolInvalidAmount();
        address lp = saucerSwapPoolStorage().lpToken;
        if (lp == address(0)) revert ISaucerSwapPool.SaucerSwapPoolNoLiquidity();
        (bool ok, bytes memory ret) = HTS_SYSTEM_CONTRACT.call(
            abi.encodeCall(IHederaTokenService.transferToken, (lp, address(this), to, amount))
        );
        int64 code = ok ? abi.decode(ret, (int64)) : HederaResponseCodes.UNKNOWN;
        if (code != HederaResponseCodes.SUCCESS) revert ISaucerSwapPool.SaucerSwapPoolTransferFailed(code);
        emit ISaucerSwapPool.LiquidityTransferred(lp, to, amount);
    }

    /// @notice See `ISaucerSwapPool.poolInfo`.
    function poolInfo() internal view returns (ISaucerSwapPool.PoolInfo memory info) {
        SaucerSwapPoolStorage storage $ = saucerSwapPoolStorage();
        info.router = $.router;
        info.factory = $.factory;
        info.whbar = $.whbar;
        if ($.router == address(0)) return info;
        info.creationFee = creationFee($);

        address token = TokenSaleLib.tokenSaleStorage().token;
        if (token == address(0)) return info;
        info.pair = ISaucerSwapV1Factory($.factory).getPair(token, $.whbar);
        if (info.pair == address(0)) return info;

        info.lpToken = ISaucerSwapV1Pair(info.pair).lpToken();
        info.lpBalance = IERC20(info.lpToken).balanceOf(address(this));
        info.lpTotalSupply = IERC20(info.lpToken).totalSupply();
        (uint112 reserve0, uint112 reserve1,) = ISaucerSwapV1Pair(info.pair).getReserves();
        (info.reserveTokens, info.reserveTinybars) = ISaucerSwapV1Pair(info.pair).token0() == token
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));
    }

    /// @notice The pair creation fee in tinybars, converted at the rate the router reads in the same transaction.
    function creationFee(SaucerSwapPoolStorage storage $) internal view returns (uint256 tinybars) {
        return HederaExchangeRateAdapterLib.tinycentsToTinybars(ISaucerSwapV1Factory($.factory).pairCreateFee());
    }

    /// @dev Allows the router exactly `units`, calls the router function that fits the pool, and withdraws whatever
    ///      allowance the router left: at an existing pool's ratio it can take fewer tokens than it was allowed.
    function _addLiquidity(SaucerSwapPoolStorage storage $, Seed memory seed)
        private
        returns (uint256 tokensTaken, uint256 tinybarsAdded, uint256 liquidity)
    {
        _approve(seed.token, $.router, seed.units);
        if (seed.created) {
            // The router takes every tinybar above the fee, so the pool opens at exactly `tinybars` to `units`. It
            // ignores the minimums here; they matter on the other branch.
            (tokensTaken, tinybarsAdded, liquidity) = ISaucerSwapV1Router($.router)
            .addLiquidityETHNewPool{ value: seed.tinybars + seed.fee }(
                seed.token, seed.units, seed.minTokens, seed.minTinybars, address(this), seed.deadline
            );
        } else {
            (tokensTaken, tinybarsAdded, liquidity) = ISaucerSwapV1Router($.router)
            .addLiquidityETH{ value: seed.tinybars }(
                seed.token, seed.units, seed.minTokens, seed.minTinybars, address(this), seed.deadline
            );
        }
        if (tokensTaken < seed.units) _approve(seed.token, $.router, 0);
    }

    /// @dev Checked here so a shortfall names itself, where the router would revert with HTS's code or a failed
    ///      HBAR transfer. The token balance is read through the token's HIP-218 ERC-20 facade.
    function _requireFunds(address token, uint256 units, uint256 tinybars) private view {
        if (address(this).balance < tinybars) {
            revert ISaucerSwapPool.SaucerSwapPoolInsufficientHbar(tinybars, address(this).balance);
        }
        uint256 held = IERC20(token).balanceOf(address(this));
        if (held < units) revert ISaucerSwapPool.SaucerSwapPoolInsufficientTokens(units, held);
    }

    /// @dev A plain `call` from the diamond, so HTS records the diamond as the owner granting the allowance.
    function _approve(address token, address spender, uint256 units) private {
        (bool ok, bytes memory ret) =
            HTS_SYSTEM_CONTRACT.call(abi.encodeCall(IHederaTokenServiceApprove.approve, (token, spender, units)));
        int64 code = ok ? abi.decode(ret, (int64)) : HederaResponseCodes.UNKNOWN;
        if (code != HederaResponseCodes.SUCCESS) revert ISaucerSwapPool.SaucerSwapPoolApproveFailed(code);
    }

    /// @dev A diamond deployed through the relay has unlimited automatic associations and would take the LP token
    ///      anyway; this covers one that does not. A new pool's LP token does not exist before the router call, so
    ///      only an existing pool's can be associated ahead of it.
    function _associate(address lp) private {
        if (IHRC719(lp).isAssociated()) return;
        (bool ok, bytes memory ret) =
            HTS_SYSTEM_CONTRACT.call(abi.encodeCall(IHederaTokenService.associateToken, (address(this), lp)));
        int64 code = ok ? abi.decode(ret, (int64)) : HederaResponseCodes.UNKNOWN;
        if (code != HederaResponseCodes.SUCCESS) revert ISaucerSwapPool.SaucerSwapPoolAssociateFailed(code);
    }
}
