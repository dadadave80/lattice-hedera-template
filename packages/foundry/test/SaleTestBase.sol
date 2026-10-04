// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { MockHederaTokenService } from "@lattice-test/mocks/hedera/MockHederaTokenService.sol";
import { HTS_SYSTEM_CONTRACT } from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import { Test } from "forge-std/Test.sol";
import { ITokenSale } from "../contracts/interfaces/ITokenSale.sol";
import { DeployDiamond } from "../script/DeployDiamond.s.sol";

/// @notice Builds the production diamond through the deploy script, with Lattice's HTS mock etched at 0x167.
///         Everything a test calls goes through the diamond, exactly as it does on Hedera.
/// @dev Uses the default recipe frozen in `test/fixtures`, not your `diamond.recipe.json`, so these tests keep
///      passing after you customize the diamond's base.
abstract contract SaleTestBase is Test {
    bytes32 internal constant HBAR_USD = "HBAR/USD";
    uint256 internal constant ONE_HBAR = 1e8; // tinybars, the unit of msg.value inside Hedera's EVM
    int64 internal constant ONE_TOKEN = 1e8; // the sale token has 8 decimals
    int64 internal constant SUPPLY = 1_000_000 * ONE_TOKEN;
    uint256 internal constant PRICE_USD = 0.05e18; // $0.05 per token
    uint256 internal constant CREATION_FEE = 20 * ONE_HBAR;

    address internal admin = makeAddr("admin");
    address internal buyer = makeAddr("buyer");

    MockHederaTokenService internal hts = MockHederaTokenService(payable(HTS_SYSTEM_CONTRACT));
    DeployDiamond internal deployer;
    address internal diamond;
    ITokenSale internal sale;

    function setUp() public virtual {
        vm.etch(HTS_SYSTEM_CONTRACT, address(new MockHederaTokenService()).code);

        deployer = new DeployDiamond();
        diamond = deployer.assemble(vm.readFile("test/fixtures/default.recipe.json"), admin);
        sale = ITokenSale(diamond);

        vm.deal(admin, 100 * ONE_HBAR);
        vm.deal(buyer, 100 * ONE_HBAR);
    }

    function _launch() internal returns (address token) {
        vm.prank(admin);
        token = sale.launchSale{ value: CREATION_FEE }("Lattice Sale Token", "LST", "", 8, SUPPLY, PRICE_USD);
    }
}
