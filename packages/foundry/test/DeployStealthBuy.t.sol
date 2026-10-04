// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { MultiInit } from "@diamond/initializers/MultiInit.sol";
import { IDiamondCut } from "@diamond/interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { FacetCut, FacetCutAction } from "@diamond/libraries/DiamondLib.sol";
import { Lattice } from "@lattice/Lattice.sol";
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
import { IERC5564Announcer } from "@lattice/interfaces/privacy/IERC5564Announcer.sol";
import { IERC6538Registry } from "@lattice/interfaces/privacy/IERC6538Registry.sol";
import { IERC165 } from "forge-std/interfaces/IERC165.sol";
import { IStealthBuy } from "../contracts/interfaces/IStealthBuy.sol";
import { DeployStealthBuy } from "../script/DeployStealthBuy.s.sol";
import { SaleTestBase } from "./SaleTestBase.sol";

/// @notice What `DeployStealthBuy` does to a diamond the template deployed before stealth purchases, such as the
///         reference diamond on Hedera testnet.
contract DeployStealthBuyTest is SaleTestBase {
    /// @dev Chains no developer deploys to, so the records these tests write never replace a real one.
    uint256 internal constant RECORDED_CHAIN = 2_960_000_001;
    uint256 internal constant UNRECORDED_CHAIN = 2_960_000_002;

    DeployStealthBuy internal script;
    address internal token;

    function setUp() public override {
        super.setUp();
        script = new DeployStealthBuy();
        token = _launch();
    }

    /// @dev The recipe before the stealth pair joined it, and `TokenSale` as the only facet of the Hedera layer.
    function _assembleDiamond() internal override returns (address) {
        (, FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls) =
            deployer.build(vm.readFile("test/fixtures/before-stealth.recipe.json"), admin);
        assembly ("memory-safe") {
            mstore(cuts, sub(mload(cuts), 1)) // StealthBuy, the last cut
        }
        Lattice lattice = new Lattice();
        lattice.initialize(cuts, address(new MultiInit()), abi.encodeCall(MultiInit.multiInit, (inits, calls)));
        return address(lattice);
    }

    function test_plan_addsTheThreeFacetsInOneCut() public {
        assertEq(IDiamondLoupe(diamond).facets().length, 9, "the diamond starts without them");
        assertEq(IDiamondLoupe(diamond).facetAddress(IStealthBuy.buyFor.selector), address(0));

        (string[] memory names, FacetCut[] memory cuts, address init, bytes memory initCalldata) = script.plan();
        vm.prank(admin);
        IDiamondCut(diamond).diamondCut(cuts, init, initCalldata);

        assertEq(names.length, 3);
        assertEq(names[0], "StealthBuy");
        assertEq(names[1], "ERC6538Registry");
        assertEq(names[2], "ERC5564Announcer");
        assertEq(IDiamondLoupe(diamond).facets().length, 12);
        for (uint256 i; i < cuts.length; ++i) {
            assertEq(uint8(cuts[i].action), uint8(FacetCutAction.Add));
            for (uint256 j; j < cuts[i].functionSelectors.length; ++j) {
                assertEq(IDiamondLoupe(diamond).facetAddress(cuts[i].functionSelectors[j]), cuts[i].facetAddress);
            }
        }
        assertEq(cuts[1].functionSelectors.length, 7, "the whole registry");
        (address saleToken,,,,,) = sale.saleInfo();
        assertEq(saleToken, token, "the sale is untouched");
    }

    function test_plan_runsTheInitsOnTheLiveDiamond() public {
        assertFalse(IERC165(diamond).supportsInterface(type(IERC6538Registry).interfaceId));
        assertFalse(IERC165(diamond).supportsInterface(type(IERC5564Announcer).interfaceId));

        (, FacetCut[] memory cuts, address init, bytes memory initCalldata) = script.plan();
        vm.prank(admin);
        IDiamondCut(diamond).diamondCut(cuts, init, initCalldata);

        assertTrue(IERC165(diamond).supportsInterface(type(IERC6538Registry).interfaceId), "ERC6538RegistryInit ran");
        assertTrue(IERC165(diamond).supportsInterface(type(IERC5564Announcer).interfaceId), "ERC5564AnnouncerInit ran");
        assertEq(
            IERC6538Registry(diamond).DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256("ERC6538Registry"),
                    keccak256("1.0"),
                    block.chainid,
                    diamond
                )
            )
        );
    }

    function test_plan_letsTheDiamondDeliverToAStealthAddress() public {
        (, FacetCut[] memory cuts, address init, bytes memory initCalldata) = script.plan();
        vm.prank(admin);
        IDiamondCut(diamond).diamondCut(cuts, init, initCalldata);
        address stealth = makeAddr("stealth");
        hts.associateToken(stealth, token); // Hedera's automatic association, which the mock lacks

        vm.prank(buyer);
        int64 tokens = IStealthBuy(diamond).buyFor{ value: 10 * ONE_HBAR + ONE_HBAR / 2 }(
            stealth, hex"02", 0x01, 40 * ONE_TOKEN, ONE_HBAR / 2
        );

        assertEq(tokens, 40 * ONE_TOKEN);
        assertEq(hts.balanceOf(token, stealth), 40 * ONE_TOKEN);
        assertEq(stealth.balance, ONE_HBAR / 2);
    }

    function test_run_cutsTheRecordedDiamondAndAddsTheFacetsToItsRecord() public {
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

        assertTrue(IDiamondLoupe(diamond).facetAddress(IStealthBuy.buyFor.selector) != address(0), "cut in");
        assertEq(vm.parseJsonAddress(record, ".address"), diamond);
        assertEq(vm.parseJsonUint(record, ".deployedOnBlock"), 41335269);
        string[] memory facets = vm.parseJsonStringArray(record, ".facets");
        assertEq(facets.length, 5);
        assertEq(facets[1], "TokenSale");
        assertEq(facets[2], "StealthBuy");
        assertEq(facets[3], "ERC6538Registry");
        assertEq(facets[4], "ERC5564Announcer");
        assertEq(vm.parseJsonStringArray(record, ".selectors.Receive")[0], "0x00000000");
        assertEq(vm.parseJsonStringArray(record, ".selectors.TokenSale").length, 6);
        string[] memory stealthBuy = vm.parseJsonStringArray(record, ".selectors.StealthBuy");
        assertEq(stealthBuy.length, 1);
        assertEq(stealthBuy[0], vm.toString(abi.encodePacked(IStealthBuy.buyFor.selector)));
        assertEq(vm.parseJsonStringArray(record, ".selectors.ERC6538Registry").length, 7);
        string[] memory announcer = vm.parseJsonStringArray(record, ".selectors.ERC5564Announcer");
        assertEq(announcer.length, 1);
        assertEq(announcer[0], vm.toString(abi.encodePacked(IERC5564Announcer.announce.selector)));
    }

    function test_run_refusesAChainWithNoRecordedDiamond() public {
        vm.chainId(UNRECORDED_CHAIN);

        vm.expectRevert(
            bytes(
                "DeployStealthBuy: no diamond is recorded in deployments/diamond/2960000002.json. Deploy one first: yarn foundry:deploy --network hedera_testnet"
            )
        );
        script.run();
    }
}
