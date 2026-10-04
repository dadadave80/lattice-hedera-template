// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { MockHederaTokenService } from "@lattice-test/mocks/hedera/MockHederaTokenService.sol";
import { HederaResponseCodes } from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import { IHederaTokenService } from "@lattice/interfaces/external/hedera/IHederaTokenService.sol";
import { EXCHANGE_RATE_SYSTEM_CONTRACT } from "@lattice/oracles/hedera/HederaExchangeRateAdapterLib.sol";
import { HTS_SYSTEM_CONTRACT } from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import { MockExchangeRate } from "./MockHedera.sol";

// SaucerSwap V1 as the router at 0.0.19264 behaves (source verified on Sourcify), reduced to what adding liquidity
// touches. The factory, router and WHBAR are etched at their testnet addresses, so they keep only immutables from
// construction and start with empty storage. Every HBAR amount is tinybars.

MockHederaTokenService constant HTS = MockHederaTokenService(payable(HTS_SYSTEM_CONTRACT));

/// @notice The WHBAR wrapping contract: the router deposits a pool's HBAR into it on the pair's behalf.
contract MockWhbar {
    mapping(address account => uint256 tinybars) public balanceOf;

    function deposit(address, address dst) external payable {
        balanceOf[dst] += msg.value;
    }
}

/// @notice A token/WHBAR pair. Its LP token is an HTS token the pair creates, treasuries and mints.
contract MockSaucerSwapV1Pair {
    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    address public immutable token0;
    address public immutable token1;
    address internal immutable WHBAR_TOKEN;
    MockWhbar internal immutable WHBAR_CONTRACT;
    address public lpToken;
    uint112 internal reserve0;
    uint112 internal reserve1;
    uint32 internal blockTimestampLast;

    /// @notice Whether `mint` associates the recipient with the LP token, as Hedera does for an account with a free
    ///         automatic association slot (HIP-904). A diamond deployed through the relay has unlimited slots.
    bool public autoAssociation = true;

    /// @dev `msg.value` pays for the LP token, out of the pair creation fee.
    constructor(address tokenA, address tokenB, address whbarToken, MockWhbar whbarContract) payable {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        WHBAR_TOKEN = whbarToken;
        WHBAR_CONTRACT = whbarContract;
        require(HTS.associateToken(address(this), _token()) == HederaResponseCodes.SUCCESS, "pair: associate");

        IHederaTokenService.HederaToken memory lp;
        lp.name = "ssLP-Lattice Sale Token-Wrapped Hbar";
        lp.symbol = "ssLP-LST-WHBAR";
        lp.treasury = address(this);
        lp.tokenKeys = new IHederaTokenService.TokenKey[](1);
        lp.tokenKeys[0].keyType = 16; // supply
        lp.tokenKeys[0].key.delegatableContractId = address(this);
        int64 code;
        (code, lpToken) = HTS.createFungibleToken{ value: msg.value }(lp, 0, 8);
        require(code == HederaResponseCodes.SUCCESS, "pair: LP token");
    }

    function setAutoAssociation(bool on) external {
        autoAssociation = on;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    /// @notice Mints LP tokens to `to` for what was deposited since the last mint, as Uniswap V2 does.
    function mint(address to) external returns (uint256 liquidity) {
        uint256 balance0 = _balanceOf(token0);
        uint256 balance1 = _balanceOf(token1);
        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;
        uint256 supply = uint256(uint64(HTS.totalSupply(lpToken)));
        uint256 minted;
        if (supply == 0) {
            liquidity = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            minted = liquidity + MINIMUM_LIQUIDITY; // the locked minimum stays with the pair
        } else {
            uint256 by0 = amount0 * supply / reserve0;
            uint256 by1 = amount1 * supply / reserve1;
            liquidity = by0 < by1 ? by0 : by1;
            minted = liquidity;
        }
        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");

        (int64 code,,) = HTS.mintToken(lpToken, int64(uint64(minted)), new bytes[](0));
        require(code == HederaResponseCodes.SUCCESS, "pair: mint LP");
        if (autoAssociation && !HTS.associated(to, lpToken)) HTS.associateToken(to, lpToken);
        code = HTS.transferToken(lpToken, address(this), to, int64(uint64(liquidity)));
        require(code == HederaResponseCodes.SUCCESS, "pair: LP transfer");

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
    }

    function _token() internal view returns (address) {
        return token0 == WHBAR_TOKEN ? token1 : token0;
    }

    function _balanceOf(address token) internal view returns (uint256) {
        if (token == WHBAR_TOKEN) return WHBAR_CONTRACT.balanceOf(address(this));
        return uint256(uint64(HTS.balanceOf(token, address(this))));
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

/// @notice SaucerSwapV1Factory: lists pairs and charges the pair creation fee, set in tinycents.
contract MockSaucerSwapV1Factory {
    address internal immutable WHBAR_TOKEN;
    MockWhbar internal immutable WHBAR_CONTRACT;

    uint256 public pairCreateFee;
    mapping(address tokenA => mapping(address tokenB => address pair)) public getPair;

    constructor(address whbarToken, MockWhbar whbarContract) {
        WHBAR_TOKEN = whbarToken;
        WHBAR_CONTRACT = whbarContract;
    }

    function setPairCreateFee(uint256 tinycents) external {
        pairCreateFee = tinycents;
    }

    function createPair(address tokenA, address tokenB) external payable returns (address pair) {
        require(getPair[tokenA][tokenB] == address(0), "UniswapV2: PAIR_EXISTS");
        uint256 fee = MockExchangeRate(EXCHANGE_RATE_SYSTEM_CONTRACT).tinycentsToTinybars(pairCreateFee);
        require(msg.value >= fee, "UniswapV2: PAIR_CREATE_FEE");
        pair = address(new MockSaucerSwapV1Pair{ value: msg.value }(tokenA, tokenB, WHBAR_TOKEN, WHBAR_CONTRACT));
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
    }
}

/// @notice SaucerSwapV1RouterV3's two ways of adding HBAR liquidity, with its checks and revert strings.
/// @dev The real router moves the caller's tokens with HTS `transferToken`, which spends the caller's allowance to
///      the router. The HTS mock models that spend as `transferFrom` from the router.
contract MockSaucerSwapV1Router {
    address public immutable factory;
    address public immutable WHBAR;
    address public immutable whbar;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    constructor(address factory_, address whbarContract, address whbarToken) {
        factory = factory_;
        WHBAR = whbarContract;
        whbar = whbarToken;
    }

    function addLiquidityETHNewPool(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        MockSaucerSwapV1Factory f = MockSaucerSwapV1Factory(factory);
        require(f.getPair(token, whbar) == address(0), "UniswapV2Router: POOL ALREADY EXISTS");
        uint256 fee = MockExchangeRate(EXCHANGE_RATE_SYSTEM_CONTRACT).tinycentsToTinybars(f.pairCreateFee());
        require(msg.value > fee, "UniswapV2Router: MSG.VALUE");
        address pair = f.createPair{ value: fee }(token, whbar);

        (amountToken, amountETH) =
            _addLiquidity(token, amountTokenDesired, msg.value - fee, amountTokenMin, amountETHMin);
        _pull(token, pair, amountToken);
        MockWhbar(WHBAR).deposit{ value: amountETH }(msg.sender, pair);
        liquidity = MockSaucerSwapV1Pair(pair).mint(to);
        if (msg.value - fee > amountETH) _refund(msg.value - fee - amountETH);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        address pair = MockSaucerSwapV1Factory(factory).getPair(token, whbar);
        require(pair != address(0), "UniswapV2Router: PAIR DOES NOT EXIST");
        (amountToken, amountETH) = _addLiquidity(token, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        _pull(token, pair, amountToken);
        MockWhbar(WHBAR).deposit{ value: amountETH }(msg.sender, pair);
        liquidity = MockSaucerSwapV1Pair(pair).mint(to);
        if (msg.value > amountETH) _refund(msg.value - amountETH);
    }

    function _addLiquidity(
        address token,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        (uint256 reserveA, uint256 reserveB) = _reserves(token);
        if (reserveA == 0 && reserveB == 0) return (amountADesired, amountBDesired);
        uint256 amountBOptimal = amountADesired * reserveB / reserveA;
        if (amountBOptimal <= amountBDesired) {
            require(amountBOptimal >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
            return (amountADesired, amountBOptimal);
        }
        uint256 amountAOptimal = amountBDesired * reserveA / reserveB;
        assert(amountAOptimal <= amountADesired);
        require(amountAOptimal >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        return (amountAOptimal, amountBDesired);
    }

    function _reserves(address token) internal view returns (uint256 reserveToken, uint256 reserveWhbar) {
        MockSaucerSwapV1Pair pair = MockSaucerSwapV1Pair(MockSaucerSwapV1Factory(factory).getPair(token, whbar));
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        return pair.token0() == token ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _pull(address token, address pair, uint256 amount) internal {
        int64 code = HTS.transferFrom(token, msg.sender, pair, amount);
        require(code == HederaResponseCodes.SUCCESS, "SafeHederaTokenService: transfer failed");
    }

    function _refund(uint256 tinybars) internal {
        (bool ok,) = msg.sender.call{ value: tinybars }("");
        require(ok, "TransferHelper: ETH_TRANSFER_FAILED");
    }
}
