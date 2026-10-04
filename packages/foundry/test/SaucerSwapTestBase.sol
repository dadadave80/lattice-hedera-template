// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { EXCHANGE_RATE_SYSTEM_CONTRACT } from "@lattice/oracles/hedera/HederaExchangeRateAdapterLib.sol";
import { HTS_SYSTEM_CONTRACT } from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import { ISaucerSwapPool } from "../contracts/interfaces/ISaucerSwapPool.sol";
import { SaleTestBase } from "./SaleTestBase.sol";
import { MockExchangeRate, MockHederaTokenServiceWithApprove, MockHtsTokenFacade } from "./mocks/MockHedera.sol";
import {
    MockSaucerSwapV1Factory,
    MockSaucerSwapV1Pair,
    MockSaucerSwapV1Router,
    MockWhbar
} from "./mocks/MockSaucerSwapV1.sol";

/// @notice `SaleTestBase` with SaucerSwap V1 mocked at its testnet addresses, which `DeployDiamond` gives the
///         diamond on any chain but mainnet, and the Exchange Rate system contract mocked at 0x168.
/// @dev The addresses are written out here rather than read from the deploy script, so a wrong constant there fails.
abstract contract SaucerSwapTestBase is SaleTestBase {
    address internal constant ROUTER = 0x0000000000000000000000000000000000004b40; // 0.0.19264
    address internal constant FACTORY = 0x00000000000000000000000000000000000026E7; // 0.0.9959
    address internal constant WHBAR_CONTRACT = 0x0000000000000000000000000000000000003aD1; // 0.0.15057
    address internal constant WHBAR = 0x0000000000000000000000000000000000003aD2; // 0.0.15058, the HTS token
    address internal constant ROUTER_MAINNET = 0x00000000000000000000000000000000002E7A5D; // 0.0.3045981
    address internal constant FACTORY_MAINNET = 0x0000000000000000000000000000000000103780; // 0.0.1062784
    address internal constant WHBAR_MAINNET = 0x0000000000000000000000000000000000163B5a; // 0.0.1456986

    /// @dev `keccak256(abi.encode(uint256(keccak256("lattice-hedera-template.storage.SaucerSwapPool")) - 1)) & ~0xff`.
    bytes32 internal constant POOL_SLOT = 0x0be13bbe52fde959265aa1b3244cb8dc1aa6979c161440fd094649e3309bd500;

    /// @dev $2.00 in tinycents, testnet's fee. At the mocked $0.20 per HBAR that is 10 HBAR.
    uint256 internal constant PAIR_CREATE_FEE_TINYCENTS = 2e10;
    uint256 internal constant POOL_FEE = 10 * ONE_HBAR;

    MockSaucerSwapV1Factory internal factory = MockSaucerSwapV1Factory(FACTORY);
    MockSaucerSwapV1Router internal router = MockSaucerSwapV1Router(ROUTER);
    MockWhbar internal whbar = MockWhbar(WHBAR_CONTRACT);
    ISaucerSwapPool internal pool;

    function setUp() public virtual override {
        super.setUp();
        pool = ISaucerSwapPool(diamond);

        // Adds `approve` to the HTS mock the diamond was built against, keeping its state.
        vm.etch(HTS_SYSTEM_CONTRACT, address(new MockHederaTokenServiceWithApprove()).code);
        vm.etch(EXCHANGE_RATE_SYSTEM_CONTRACT, address(new MockExchangeRate()).code);
        MockExchangeRate(EXCHANGE_RATE_SYSTEM_CONTRACT).setRate(20, 1); // $0.20 per HBAR, as the mocked feed says

        vm.etch(WHBAR_CONTRACT, address(new MockWhbar()).code);
        vm.etch(FACTORY, address(new MockSaucerSwapV1Factory(WHBAR, whbar)).code);
        factory.setPairCreateFee(PAIR_CREATE_FEE_TINYCENTS);
        vm.etch(ROUTER, address(new MockSaucerSwapV1Router(FACTORY, WHBAR_CONTRACT, WHBAR)).code);
    }

    /// @dev Launches the sale and gives its token the ERC-20 reads the facet uses.
    function _launchPoolable() internal returns (address token) {
        token = _launch();
        _withFacade(token);
    }

    /// @dev Lattice's token mock answers only HIP-719; this one also answers `balanceOf` and `totalSupply`.
    function _withFacade(address token) internal {
        vm.etch(token, address(new MockHtsTokenFacade()).code);
    }

    /// @dev Buys `tinybars` worth of the sale's token as `who`, which puts `tinybars` of proceeds in the diamond.
    function _buy(address who, address token, uint256 tinybars) internal returns (int64 tokens) {
        vm.startPrank(who);
        if (!hts.associated(who, token)) MockHtsTokenFacade(token).associate();
        tokens = sale.buy{ value: tinybars }(0);
        vm.stopPrank();
    }

    /// @dev Seeds with 99% minimums, as the facet's NatSpec tells an admin to.
    function _seed(int64 tokens, uint256 tinybars) internal returns (int64, uint256, uint256) {
        return _seed(tokens, tinybars, tokens * 99 / 100, tinybars * 99 / 100);
    }

    function _seed(int64 tokens, uint256 tinybars, int64 minTokens, uint256 minTinybars)
        internal
        returns (int64, uint256, uint256)
    {
        vm.prank(admin);
        return pool.seedPool(tokens, tinybars, minTokens, minTinybars, type(uint256).max, block.timestamp);
    }

    function _pair(address token) internal view returns (MockSaucerSwapV1Pair) {
        return MockSaucerSwapV1Pair(factory.getPair(token, WHBAR));
    }

    /// @dev Word `index` of the facet's storage: 0 router, 1 factory, 2 WHBAR, 3 pair, 4 LP token.
    function _stored(address target, uint256 index) internal view returns (address) {
        return address(uint160(uint256(vm.load(target, bytes32(uint256(POOL_SLOT) + index)))));
    }
}
