// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IEmergencyStop } from "@lattice/interfaces/security/IEmergencyStop.sol";
import { Test } from "forge-std/Test.sol";
import { DeployDiamond } from "../script/DeployDiamond.s.sol";

/// @dev Opens the guardian step `run()` takes after the diamond exists, and the check `build()` runs on the
///      Hedera layer, so both can be tested without a broadcast.
contract DeployGuardianHarness is DeployDiamond {
    function addGuardian(address diamond) external {
        _addGuardian(diamond, address(this));
    }

    function requireProjectFacets(string[] memory names, uint256 first) external view {
        _requireProjectFacets(names, first);
    }
}

contract DeployGuardianTest is Test {
    DeployGuardianHarness internal deployer;
    string internal recipe;

    function setUp() public {
        deployer = new DeployGuardianHarness();
        recipe = vm.readFile("test/fixtures/default.recipe.json");
    }

    function test_addGuardian_makesTheDeployerAGuardianWhoCanStopTheSale() public {
        address diamond = deployer.assemble(recipe, address(deployer));

        deployer.addGuardian(diamond);

        assertTrue(IEmergencyStop(diamond).isGuardian(address(deployer)));
        vm.prank(address(deployer));
        IEmergencyStop(diamond).emergencyStop("oracle incident");
        assertTrue(IEmergencyStop(diamond).isStopped());
    }

    function test_addGuardian_leavesTheGuardianToARecipeAdminThatIsNotTheDeployer() public {
        string memory json = vm.replace(
            recipe,
            '{\n            "$ref": "deployer"\n          }',
            string.concat('"', vm.toString(makeAddr("safe")), '"')
        );
        address diamond = deployer.assemble(json, address(deployer));

        deployer.addGuardian(diamond); // must not revert

        assertFalse(IEmergencyStop(diamond).isGuardian(address(deployer)));
    }

    function test_addGuardian_skipsADiamondWithoutEmergencyStop() public {
        address diamond = deployer.assemble(vm.replace(recipe, '"EmergencyStop",', ""), address(deployer));

        deployer.addGuardian(diamond); // must not revert
    }

    function test_build_acceptsAProjectFacetCompiledFromAFileOfItsName() public view {
        string[] memory names = new string[](3);
        names[0] = "TokenSale";
        names[1] = "StealthBuy";
        names[2] = "TokenSaleV2";

        deployer.requireProjectFacets(names, 0);
    }

    function test_build_revertsWhenHederaFacetsCountsASlotNoFacetFills() public {
        string[] memory names = new string[](3);
        names[0] = "TokenSale";
        names[1] = "StealthBuy";

        vm.expectRevert(
            bytes("DeployDiamond: HEDERA_FACETS is higher than the number of facets build() appends after the recipe's")
        );
        deployer.requireProjectFacets(names, 0);
    }

    function test_build_revertsWhenAProjectFacetHasNoArtifactUnderItsName() public {
        // A `Referral` contract in contracts/ReferralFacet.sol compiles to out/ReferralFacet.sol/Referral.json.
        string[] memory names = new string[](1);
        names[0] = "Referral";

        vm.expectRevert(
            bytes(
                "DeployDiamond: Referral has no artifact at out/Referral.sol/Referral.json; put the contract in contracts/Referral.sol, a file named after it"
            )
        );
        deployer.requireProjectFacets(names, 0);
    }
}
