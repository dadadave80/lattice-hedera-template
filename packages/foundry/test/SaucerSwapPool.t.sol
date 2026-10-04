// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { HederaResponseCodes } from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import { IHederaTokenService } from "@lattice/interfaces/external/hedera/IHederaTokenService.sol";
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
import { IERC8153 } from "@lattice/interfaces/external/ercs/IERC8153.sol";
import { IEmergencyStop } from "@lattice/interfaces/security/IEmergencyStop.sol";
import { ISaucerSwapPool } from "../contracts/interfaces/ISaucerSwapPool.sol";
import { IHederaTokenServiceApprove } from "../contracts/interfaces/ISaucerSwapV1.sol";
import { ITokenSale } from "../contracts/interfaces/ITokenSale.sol";
import { SaucerSwapTestBase } from "./SaucerSwapTestBase.sol";
import { MockSaucerSwapV1Pair } from "./mocks/MockSaucerSwapV1.sol";

contract SaucerSwapPoolTest is SaucerSwapTestBase {
    /// @dev What the buyer pays before every seeding test, so the diamond holds sale proceeds.
    uint256 internal constant PROCEEDS = 50 * ONE_HBAR;
    /// @dev At $0.05 per token and $0.20 per HBAR, 20 HBAR buys 80 tokens.
    uint256 internal constant POOL_HBAR = 20 * ONE_HBAR;
    int64 internal constant POOL_TOKENS = 80 * ONE_TOKEN;
    /// @dev The first deposit's liquidity: sqrt(80e8 * 20e8) less the 1000 units the pair locks.
    uint256 internal constant FIRST_LIQUIDITY = 40e8 - 1000;

    address internal token;

    function _ready() internal {
        token = _launchPoolable();
        _buy(buyer, token, PROCEEDS);
    }

    // ── a new pool ──────────────────────────────────────────────────────────────────────────────────

    function test_seedPool_createsThePoolAtTheSalePrice() public {
        _ready();
        assertEq(sale.quote(POOL_HBAR), POOL_TOKENS, "the sale's price for 20 HBAR");

        vm.expectEmit(false, false, false, true, diamond);
        emit ISaucerSwapPool.PoolSeeded(address(0), address(0), true, POOL_TOKENS, POOL_HBAR, FIRST_LIQUIDITY, POOL_FEE);
        (int64 tokens, uint256 tinybars, uint256 liquidity) = _seed(sale.quote(POOL_HBAR), POOL_HBAR);

        assertEq(tokens, POOL_TOKENS);
        assertEq(tinybars, POOL_HBAR);
        assertEq(liquidity, FIRST_LIQUIDITY);
        MockSaucerSwapV1Pair pair = _pair(token);
        assertTrue(address(pair) != address(0), "the factory lists the pair");
        (uint256 reserveTokens, uint256 reserveTinybars) = _reserves(pair);
        assertEq(reserveTokens, uint256(uint64(POOL_TOKENS)));
        assertEq(reserveTinybars, POOL_HBAR);
        assertEq(reserveTokens * ONE_HBAR / reserveTinybars, uint256(uint64(sale.quote(ONE_HBAR))), "the sale price");

        assertEq(diamond.balance, PROCEEDS - POOL_HBAR - POOL_FEE, "the pool's HBAR and the creation fee");
        assertEq(hts.balanceOf(token, diamond), SUPPLY - 200 * ONE_TOKEN - POOL_TOKENS);
        assertEq(hts.balanceOf(pair.lpToken(), diamond), int64(uint64(FIRST_LIQUIDITY)), "the diamond holds the LP");
        assertEq(_stored(diamond, 3), address(pair), "pair recorded");
        assertEq(_stored(diamond, 4), pair.lpToken(), "LP token recorded");
    }

    function test_seedPool_takesTheHbarTheAdminSendsWithTheCall() public {
        token = _launchPoolable();
        assertEq(diamond.balance, 0, "no proceeds yet");
        uint256 before = admin.balance;

        vm.prank(admin);
        pool.seedPool{ value: POOL_HBAR + POOL_FEE }(POOL_TOKENS, POOL_HBAR, 0, 0, POOL_FEE, block.timestamp);

        assertEq(admin.balance, before - POOL_HBAR - POOL_FEE);
        assertEq(diamond.balance, 0);
        (, uint256 reserveTinybars) = _reserves(_pair(token));
        assertEq(reserveTinybars, POOL_HBAR);
    }

    function test_seedPool_leavesNoAllowanceBehind() public {
        _ready();

        _seed(POOL_TOKENS, POOL_HBAR);

        assertEq(hts.allowances(token, diamond, ROUTER), 0);
    }

    function test_seedPool_revertsWhenTheCreationFeeIsAboveTheCallersLimit() public {
        _ready();

        vm.expectRevert(
            abi.encodeWithSelector(ISaucerSwapPool.SaucerSwapPoolCreationFeeTooHigh.selector, POOL_FEE, POOL_FEE - 1)
        );
        vm.prank(admin);
        pool.seedPool(POOL_TOKENS, POOL_HBAR, 0, 0, POOL_FEE - 1, block.timestamp);
    }

    function test_seedPool_revertsWhenTheDiamondCannotPayThePoolAndTheFee() public {
        _ready();
        uint256 tinybars = PROCEEDS - POOL_FEE + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ISaucerSwapPool.SaucerSwapPoolInsufficientHbar.selector, tinybars + POOL_FEE, PROCEEDS
            )
        );
        _seed(POOL_TOKENS, tinybars);
    }

    function test_seedPool_revertsWhenTheTreasuryHoldsTooFewTokens() public {
        _ready();
        uint256 held = uint256(uint64(SUPPLY - 200 * ONE_TOKEN));

        vm.expectRevert(
            abi.encodeWithSelector(
                ISaucerSwapPool.SaucerSwapPoolInsufficientTokens.selector, uint256(uint64(SUPPLY)), held
            )
        );
        _seed(SUPPLY, POOL_HBAR);
    }

    function test_seedPool_revertsAfterTheDeadline() public {
        _ready();

        uint256 deadline = block.timestamp;
        skip(1);

        vm.expectRevert(bytes("UniswapV2Router: EXPIRED"));
        vm.prank(admin);
        pool.seedPool(POOL_TOKENS, POOL_HBAR, 0, 0, POOL_FEE, deadline);
    }

    // ── an existing pool ────────────────────────────────────────────────────────────────────────────

    function test_seedPool_topsUpAtThePoolsRatioAndWithdrawsTheUnusedAllowance() public {
        _ready();
        _seed(POOL_TOKENS, POOL_HBAR);
        uint256 balance = diamond.balance;

        // 20 HBAR takes 80 tokens at 4 per HBAR, so 20 of the 100 allowed stay unused.
        vm.expectEmit(diamond);
        emit ISaucerSwapPool.PoolSeeded(
            address(_pair(token)), _pair(token).lpToken(), false, POOL_TOKENS, POOL_HBAR, 40e8, 0
        );
        (int64 tokens, uint256 tinybars, uint256 liquidity) = _seed(100 * ONE_TOKEN, POOL_HBAR);

        assertEq(tokens, POOL_TOKENS);
        assertEq(tinybars, POOL_HBAR);
        assertEq(liquidity, 40e8, "as much again as the pool held");
        assertEq(diamond.balance, balance - POOL_HBAR, "no creation fee the second time");
        assertEq(hts.allowances(token, diamond, ROUTER), 0, "the 20 tokens the router did not take");
        assertEq(hts.balanceOf(_pair(token).lpToken(), diamond), int64(uint64(FIRST_LIQUIDITY + 40e8)));
    }

    function test_seedPool_keepsTheHbarTheRouterSendsBack() public {
        _ready();
        _seed(POOL_TOKENS, POOL_HBAR);
        uint256 balance = diamond.balance;

        // 40 tokens need only 10 of the 20 HBAR; the router refunds the rest through the `Receive` facet.
        (int64 tokens, uint256 tinybars,) = _seed(40 * ONE_TOKEN, POOL_HBAR);

        assertEq(tokens, 40 * ONE_TOKEN);
        assertEq(tinybars, 10 * ONE_HBAR);
        assertEq(diamond.balance, balance - 10 * ONE_HBAR);
        assertEq(hts.allowances(token, diamond, ROUTER), 0);
    }

    function test_seedPool_revertsWhenThePoolWouldTakeTooFewTokens() public {
        _ready();
        _seed(POOL_TOKENS, POOL_HBAR);

        // 20 HBAR takes only 80 of the 100 tokens offered.
        vm.expectRevert(bytes("UniswapV2Router: INSUFFICIENT_A_AMOUNT"));
        vm.prank(admin);
        pool.seedPool(100 * ONE_TOKEN, POOL_HBAR, 90 * ONE_TOKEN, 0, 0, block.timestamp);
    }

    function test_seedPool_revertsWhenThePoolWouldTakeTooLittleHbar() public {
        _ready();
        _seed(POOL_TOKENS, POOL_HBAR);

        // 40 tokens take only 10 of the 20 HBAR offered.
        vm.expectRevert(bytes("UniswapV2Router: INSUFFICIENT_B_AMOUNT"));
        vm.prank(admin);
        pool.seedPool(40 * ONE_TOKEN, POOL_HBAR, 0, 15 * ONE_HBAR, 0, block.timestamp);
    }

    function test_seedPool_refusesAPoolSomeoneSkewedFirstUnlessTheMinimumsAllowIt() public {
        _ready();
        // A holder opens the pool first at 100 tokens per HBAR, 25 times cheaper than the sale.
        _openPoolAs(buyer, 100 * ONE_TOKEN, ONE_HBAR);

        vm.expectRevert(bytes("UniswapV2Router: INSUFFICIENT_B_AMOUNT"));
        vm.prank(admin);
        pool.seedPool(POOL_TOKENS, POOL_HBAR, POOL_TOKENS, POOL_HBAR * 95 / 100, 0, block.timestamp);
    }

    function test_seedPool_associatesTheDiamondWithAnExistingPoolsLpToken() public {
        _ready();
        _openPoolAs(buyer, 100 * ONE_TOKEN, ONE_HBAR);
        MockSaucerSwapV1Pair pair = _pair(token);
        pair.setAutoAssociation(false); // the LP transfer now fails unless the facet associated the diamond
        assertFalse(hts.associated(diamond, pair.lpToken()));

        (int64 tokens, uint256 tinybars, uint256 liquidity) = _seed(100 * ONE_TOKEN, ONE_HBAR);

        assertEq(tokens, 100 * ONE_TOKEN);
        assertEq(tinybars, ONE_HBAR);
        assertTrue(hts.associated(diamond, pair.lpToken()));
        assertEq(hts.balanceOf(pair.lpToken(), diamond), int64(uint64(liquidity)));
        assertEq(_stored(diamond, 3), address(pair), "the pool the diamond did not create is recorded");
    }

    function test_seedPool_revertsWhenHtsRefusesTheLpAssociation() public {
        _ready();
        _openPoolAs(buyer, 100 * ONE_TOKEN, ONE_HBAR);
        _pair(token).setAutoAssociation(false);
        hts.force(IHederaTokenService.associateToken.selector, HederaResponseCodes.INVALID_TOKEN_ID);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISaucerSwapPool.SaucerSwapPoolAssociateFailed.selector, HederaResponseCodes.INVALID_TOKEN_ID
            )
        );
        _seed(100 * ONE_TOKEN, ONE_HBAR);
    }

    // ── guards ──────────────────────────────────────────────────────────────────────────────────────

    function test_seedPool_revertsForAnyoneButTheAdmin() public {
        _ready();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, buyer, bytes32(0))
        );
        vm.prank(buyer);
        pool.seedPool(POOL_TOKENS, POOL_HBAR, 0, 0, POOL_FEE, block.timestamp);
    }

    function test_seedPool_revertsWhileTheEmergencyStopIsActive() public {
        _ready();
        vm.startPrank(admin);
        IEmergencyStop(diamond).addGuardian(admin);
        IEmergencyStop(diamond).emergencyStop("oracle incident");

        vm.expectRevert(IEmergencyStop.EmergencyStopActive.selector);
        pool.seedPool(POOL_TOKENS, POOL_HBAR, 0, 0, POOL_FEE, block.timestamp);
        vm.stopPrank();
    }

    function test_seedPool_revertsBeforeTheSaleLaunches() public {
        vm.expectRevert(ITokenSale.TokenSaleNotLaunched.selector);
        _seed(POOL_TOKENS, POOL_HBAR);
    }

    function test_seedPool_revertsOnAnAmountItCannotAdd() public {
        _ready();

        vm.startPrank(admin);
        vm.expectRevert(ISaucerSwapPool.SaucerSwapPoolInvalidAmount.selector);
        pool.seedPool(0, POOL_HBAR, 0, 0, POOL_FEE, block.timestamp);
        vm.expectRevert(ISaucerSwapPool.SaucerSwapPoolInvalidAmount.selector);
        pool.seedPool(POOL_TOKENS, 0, 0, 0, POOL_FEE, block.timestamp);
        vm.expectRevert(ISaucerSwapPool.SaucerSwapPoolInvalidAmount.selector);
        pool.seedPool(POOL_TOKENS, POOL_HBAR, -1, 0, POOL_FEE, block.timestamp);
        vm.stopPrank();
    }

    function test_seedPool_revertsWhenHtsRefusesTheAllowance() public {
        _ready();
        hts.force(IHederaTokenServiceApprove.approve.selector, HederaResponseCodes.UNKNOWN);

        vm.expectRevert(
            abi.encodeWithSelector(ISaucerSwapPool.SaucerSwapPoolApproveFailed.selector, HederaResponseCodes.UNKNOWN)
        );
        _seed(POOL_TOKENS, POOL_HBAR);
    }

    function test_seedPool_revertsWithoutItsInitializer() public {
        _ready();
        vm.store(diamond, POOL_SLOT, bytes32(0)); // the router, as if the facet were cut in without its init

        vm.expectRevert(ISaucerSwapPool.SaucerSwapPoolNotConfigured.selector);
        _seed(POOL_TOKENS, POOL_HBAR);
    }

    // ── the sale afterwards ─────────────────────────────────────────────────────────────────────────

    function test_sale_keepsSellingAtItsPriceAfterThePoolOpens() public {
        _ready();
        _seed(POOL_TOKENS, POOL_HBAR);
        (,,,, int64 soldBefore, uint256 raisedBefore) = sale.saleInfo();

        int64 tokens = _buy(buyer, token, 10 * ONE_HBAR);

        assertEq(tokens, 40 * ONE_TOKEN);
        (,,,, int64 sold, uint256 raised) = sale.saleInfo();
        assertEq(sold, soldBefore + 40 * ONE_TOKEN, "seeding is not a sale");
        assertEq(raised, raisedBefore + 10 * ONE_HBAR);
    }

    // ── the view ────────────────────────────────────────────────────────────────────────────────────

    function test_poolInfo_showsTheAddressesAndTheFeeBeforeThereIsAPool() public view {
        ISaucerSwapPool.PoolInfo memory info = pool.poolInfo();

        assertEq(info.router, ROUTER);
        assertEq(info.factory, FACTORY);
        assertEq(info.whbar, WHBAR);
        assertEq(info.creationFee, POOL_FEE, "$2 at $0.20 per HBAR");
        assertEq(info.pair, address(0));
        assertEq(info.lpToken, address(0));
        assertEq(info.lpBalance, 0);
    }

    function test_poolInfo_showsThePoolAndTheDiamondsShare() public {
        _ready();
        _seed(POOL_TOKENS, POOL_HBAR);
        MockSaucerSwapV1Pair pair = _pair(token);
        _withFacade(pair.lpToken());

        ISaucerSwapPool.PoolInfo memory info = pool.poolInfo();

        assertEq(info.pair, address(pair));
        assertEq(info.lpToken, pair.lpToken());
        assertEq(info.lpBalance, FIRST_LIQUIDITY);
        assertEq(info.lpTotalSupply, FIRST_LIQUIDITY + 1000, "the locked minimum counts");
        assertEq(info.reserveTokens, uint256(uint64(POOL_TOKENS)));
        assertEq(info.reserveTinybars, POOL_HBAR);
        assertEq(info.creationFee, POOL_FEE);
    }

    function test_poolInfo_showsAPoolSomeoneElseCreated() public {
        _ready();
        _openPoolAs(buyer, 100 * ONE_TOKEN, ONE_HBAR);
        _withFacade(_pair(token).lpToken());

        ISaucerSwapPool.PoolInfo memory info = pool.poolInfo();

        assertEq(info.pair, address(_pair(token)));
        assertEq(info.lpBalance, 0);
        assertEq(info.reserveTokens, uint256(uint64(100 * ONE_TOKEN)));
        assertEq(info.reserveTinybars, ONE_HBAR);
    }

    // ── the facet and its deployment ────────────────────────────────────────────────────────────────

    function test_exportSelectors_matchesTheAbi() public view {
        address facet = IDiamondLoupe(diamond).facetAddress(ISaucerSwapPool.seedPool.selector);
        bytes memory exported = IERC8153(facet).exportSelectors();

        assertEq(exported.length, 2 * 4);
        _assertExportsItsAbi("SaucerSwapPool", exported);
        for (uint256 i; i < exported.length / 4; ++i) {
            assertEq(IDiamondLoupe(diamond).facetAddress(_selectorAt(exported, i)), facet, "routed to the facet");
        }
    }

    function test_deployDiamond_givesTheFacetTestnetAddressesOffMainnet() public view {
        assertEq(_stored(diamond, 0), ROUTER);
        assertEq(_stored(diamond, 1), FACTORY);
        assertEq(_stored(diamond, 2), WHBAR);
    }

    function test_deployDiamond_givesTheFacetMainnetAddressesOnMainnet() public {
        vm.chainId(295);
        address mainnet = deployer.assemble(vm.readFile("test/fixtures/default.recipe.json"), admin);

        assertEq(_stored(mainnet, 0), ROUTER_MAINNET);
        assertEq(_stored(mainnet, 1), FACTORY_MAINNET);
        assertEq(_stored(mainnet, 2), WHBAR_MAINNET);
    }

    // ── helpers ─────────────────────────────────────────────────────────────────────────────────────

    /// @dev `who` buys tokens from the sale and creates the pool with them directly through the router.
    function _openPoolAs(address who, int64 tokens, uint256 tinybars) internal {
        vm.deal(who, who.balance + tinybars + POOL_FEE);
        vm.startPrank(who);
        IHederaTokenServiceApprove(address(hts)).approve(token, ROUTER, uint256(uint64(tokens)));
        router.addLiquidityETHNewPool{ value: tinybars + POOL_FEE }(
            token, uint256(uint64(tokens)), 0, 0, who, block.timestamp
        );
        vm.stopPrank();
    }

    function _reserves(MockSaucerSwapV1Pair pair) internal view returns (uint256 tokens, uint256 tinybars) {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        return pair.token0() == token ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), reserve0);
    }
}
