// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { MultiInit } from "@diamond/initializers/MultiInit.sol";
import { IDiamondCut } from "@diamond/interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { FacetCut, FacetCutAction } from "@diamond/libraries/DiamondLib.sol";
import { Lattice } from "@lattice/Lattice.sol";
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
import { SaucerSwapPoolInit } from "../contracts/SaucerSwapPoolInit.sol";
import { ISaucerSwapPool } from "../contracts/interfaces/ISaucerSwapPool.sol";
import { DeploySaucerSwapPool } from "../script/DeploySaucerSwapPool.s.sol";
import { SaucerSwapTestBase } from "./SaucerSwapTestBase.sol";

/// @notice What `DeploySaucerSwapPool` does to a diamond the template deployed before SaucerSwap pooling, such as
///         the reference diamond on Hedera testnet.
contract DeploySaucerSwapPoolTest is SaucerSwapTestBase {
    /// @dev Chains no developer deploys to, so the records these tests write never replace a real one.
    uint256 internal constant RECORDED_CHAIN = 2_960_000_004;
    uint256 internal constant UNRECORDED_CHAIN = 2_960_000_005;

    DeploySaucerSwapPool internal script;

    function setUp() public override {
        super.setUp();
        script = new DeploySaucerSwapPool();
    }

    /// @dev The default diamond without `SaucerSwapPool` and without its initializer, so only the script's cut can
    ///      configure the facet.
    function _assembleDiamond() internal override returns (address) {
        (string[] memory names, FacetCut[] memory allCuts, address[] memory allInits, bytes[] memory allCalls) =
            deployer.build(vm.readFile("test/fixtures/default.recipe.json"), admin);
        FacetCut[] memory cuts = new FacetCut[](allCuts.length - 1);
        uint256 n;
        for (uint256 i; i < allCuts.length; ++i) {
            if (keccak256(bytes(names[i])) != keccak256("SaucerSwapPool")) cuts[n++] = allCuts[i];
        }
        address[] memory inits = new address[](allInits.length - 1);
        bytes[] memory calls = new bytes[](allInits.length - 1);
        n = 0;
        for (uint256 i; i < allInits.length; ++i) {
            if (bytes4(allCalls[i]) == SaucerSwapPoolInit.init.selector) continue;
            inits[n] = allInits[i];
            calls[n++] = allCalls[i];
        }
        Lattice lattice = new Lattice();
        lattice.initialize(cuts, address(new MultiInit()), abi.encodeCall(MultiInit.multiInit, (inits, calls)));
        return address(lattice);
    }

    function test_plan_addsTheFacetInOneCutAndRunsItsInit() public {
        uint256 before = IDiamondLoupe(diamond).facets().length;
        assertEq(IDiamondLoupe(diamond).facetAddress(ISaucerSwapPool.seedPool.selector), address(0), "no facet yet");
        assertEq(_stored(diamond, 0), address(0), "no router yet");

        (string[] memory names, FacetCut[] memory cuts, address init, bytes memory initCalldata) = script.plan();
        vm.prank(admin);
        IDiamondCut(diamond).diamondCut(cuts, init, initCalldata);

        assertEq(names.length, 1);
        assertEq(names[0], "SaucerSwapPool");
        assertEq(IDiamondLoupe(diamond).facets().length, before + 1);
        assertEq(uint8(cuts[0].action), uint8(FacetCutAction.Add));
        assertEq(cuts[0].functionSelectors.length, 2);
        for (uint256 j; j < cuts[0].functionSelectors.length; ++j) {
            assertEq(IDiamondLoupe(diamond).facetAddress(cuts[0].functionSelectors[j]), cuts[0].facetAddress);
        }
        assertEq(_stored(diamond, 0), ROUTER, "SaucerSwapPoolInit ran through UpgradeMultiInit");
        assertEq(_stored(diamond, 1), FACTORY);
        assertEq(_stored(diamond, 2), WHBAR);
    }

    function test_plan_givesTheFacetMainnetAddressesOnMainnet() public {
        vm.chainId(295);

        (, FacetCut[] memory cuts, address init, bytes memory initCalldata) = script.plan();
        vm.prank(admin);
        IDiamondCut(diamond).diamondCut(cuts, init, initCalldata);

        assertEq(_stored(diamond, 0), ROUTER_MAINNET);
        assertEq(_stored(diamond, 1), FACTORY_MAINNET);
        assertEq(_stored(diamond, 2), WHBAR_MAINNET);
    }

    function test_plan_letsTheDiamondSeedAPool() public {
        (, FacetCut[] memory cuts, address init, bytes memory initCalldata) = script.plan();
        vm.prank(admin);
        IDiamondCut(diamond).diamondCut(cuts, init, initCalldata);
        address token = _launchPoolable();
        _buy(buyer, token, 50 * ONE_HBAR);

        (int64 tokens, uint256 tinybars, uint256 liquidity) = _seed(80 * ONE_TOKEN, 20 * ONE_HBAR);

        assertEq(tokens, 80 * ONE_TOKEN);
        assertEq(tinybars, 20 * ONE_HBAR);
        assertEq(liquidity, 40e8 - 1000);
        assertTrue(address(_pair(token)) != address(0));
    }

    function test_run_cutsTheRecordedDiamondAndAddsTheFacetToItsRecord() public {
        vm.chainId(RECORDED_CHAIN);
        string memory path = string.concat("deployments/diamond/", vm.toString(RECORDED_CHAIN), ".json");
        vm.createDir("deployments/diamond", true);
        vm.writeFile(
            path,
            string.concat(
                '{"address":"',
                vm.toString(diamond),
                '","deployedOnBlock":41335269,"facets":["Receive","TokenSale"],"selectors":{"Receive":["0x00000000"],',
                '"TokenSale":["0x08bf598d","0xdf1d74ae","0xed1bd76c","0x8e3695b8","0x1919fed7","0x970ea83e"]}}'
            )
        );
        vm.prank(admin);
        IAccessControl(diamond).grantRole(bytes32(0), DEFAULT_SENDER); // the account `run` broadcasts from here

        script.run();
        string memory record = vm.readFile(path);
        vm.removeFile(path);

        assertTrue(IDiamondLoupe(diamond).facetAddress(ISaucerSwapPool.seedPool.selector) != address(0), "cut in");
        assertEq(_stored(diamond, 0), ROUTER, "testnet addresses off mainnet");
        assertEq(vm.parseJsonAddress(record, ".address"), diamond);
        assertEq(vm.parseJsonUint(record, ".deployedOnBlock"), 41335269);
        string[] memory facets = vm.parseJsonStringArray(record, ".facets");
        assertEq(facets.length, 3);
        assertEq(facets[0], "Receive");
        assertEq(facets[1], "TokenSale");
        assertEq(facets[2], "SaucerSwapPool");
        assertEq(vm.parseJsonStringArray(record, ".selectors.TokenSale").length, 6);
        string[] memory selectors = vm.parseJsonStringArray(record, ".selectors.SaucerSwapPool");
        assertEq(selectors.length, 2);
        assertEq(selectors[0], vm.toString(abi.encodePacked(ISaucerSwapPool.seedPool.selector)));
        assertEq(selectors[1], vm.toString(abi.encodePacked(ISaucerSwapPool.poolInfo.selector)));
    }

    function test_run_refusesAChainWithNoRecordedDiamond() public {
        vm.chainId(UNRECORDED_CHAIN);

        vm.expectRevert(
            bytes(
                "DeploySaucerSwapPool: no diamond is recorded in deployments/diamond/2960000005.json. Deploy one first: yarn foundry:deploy --network hedera_testnet"
            )
        );
        script.run();
    }
}
