// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { MultiInit } from "@diamond/initializers/MultiInit.sol";
import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { Facet, FacetCut } from "@diamond/libraries/DiamondLib.sol";
import { Lattice } from "@lattice/Lattice.sol";
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
import { IChainlinkAdapter } from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
import { IHTSAdapter } from "@lattice/interfaces/tokens/IHTSAdapter.sol";
import { Test } from "forge-std/Test.sol";
import { ITokenSale } from "../contracts/interfaces/ITokenSale.sol";
import { DeployDiamond } from "../script/DeployDiamond.s.sol";
import { MockAggregatorV3 } from "./mocks/MockAggregatorV3.sol";

/// @dev Opens the step `run()` performs after the diamond exists, so it can be tested without a broadcast.
contract DeployDiamondHarness is DeployDiamond {
    function registerHbarUsdFeed(address diamond) external {
        _registerHbarUsdFeed(diamond);
    }
}

contract DeployDiamondTest is Test {
    address internal constant HBAR_USD_FEED_TESTNET = 0x59bC155EB6c6C415fE43255aF66EcF0523c92B4a;

    address internal admin = makeAddr("admin");
    DeployDiamondHarness internal deployer;
    string internal recipe;

    function setUp() public {
        deployer = new DeployDiamondHarness();
        recipe = vm.readFile("test/fixtures/default.recipe.json");
    }

    /// @dev The one test that reads your own `diamond.recipe.json`. It stays green as long as that file builds.
    function test_projectRecipe_buildsADiamondWithTheHederaLayer() public {
        (address diamond,,) = _diamond(vm.readFile("diamond.recipe.json"));
        assertTrue(IDiamondLoupe(diamond).facetAddress(ITokenSale.saleInfo.selector) != address(0), "TokenSale");

        assertTrue(
            IDiamondLoupe(diamond).facetAddress(IHTSAdapter.createFungibleToken.selector) != address(0), "HTSAdapter"
        );
    }

    function test_defaultRecipe_buildsTheBaseAndTheHederaLayer() public {
        (address diamond, string[] memory names, FacetCut[] memory cuts) = _diamond(recipe);

        assertEq(names.length, 9, "seven base facets, HTSAdapter and TokenSale");
        assertEq(names[7], "HTSAdapter");
        assertEq(names[8], "TokenSale");

        Facet[] memory facets = IDiamondLoupe(diamond).facets();
        assertEq(facets.length, 9);

        uint256 baseSelectors;
        for (uint256 i; i < cuts.length; ++i) {
            if (i < 7) baseSelectors += cuts[i].functionSelectors.length;
            for (uint256 j; j < cuts[i].functionSelectors.length; ++j) {
                assertEq(
                    IDiamondLoupe(diamond).facetAddress(cuts[i].functionSelectors[j]),
                    cuts[i].facetAddress,
                    string.concat("a ", names[i], " selector is routed elsewhere")
                );
            }
        }
        assertEq(baseSelectors, 24, "the selector count Lattice Studio plans for the default base");
    }

    function test_defaultRecipe_makesTheAdminTheAdminOfEveryLayer() public {
        (address diamond,,) = _diamond(recipe);

        assertTrue(IAccessControl(diamond).hasRole(bytes32(0), admin), "DEFAULT_ADMIN_ROLE");
        assertTrue(IAccessControl(diamond).hasRole(keccak256("HTS_MANAGER_ROLE"), admin), "HTS_MANAGER_ROLE");
        (,,, bytes32 feedKey,,) = ITokenSale(diamond).saleInfo();
        assertEq(feedKey, bytes32("HBAR/USD"), "TokenSaleInit ran");
    }

    function test_build_revertsWhenAFacetIsNotCompiledIn() public {
        string memory json = vm.replace(recipe, '"ERC165Facet"', '"ERC165Facet", "RateLimiter"');

        vm.expectRevert(
            bytes(
                "Recipe: RateLimiter is in the recipe but not compiled into this project; add its import to contracts/LatticeFacets.sol"
            )
        );
        deployer.build(json, admin);
    }

    function test_build_revertsWhenAFacetIsNotALatticeFacet() public {
        // TokenSale is compiled into the project, but it is this project's facet, not one of Lattice's.
        string memory json = vm.replace(recipe, '"ERC165Facet"', '"ERC165Facet", "TokenSale"');

        vm.expectRevert(bytes("BaseDeploy: TokenSale is not in FacetInventory"));
        deployer.build(json, admin);
    }

    function test_build_revertsOnAFileThatIsNotARecipe() public {
        vm.expectRevert(bytes("Recipe: diamond.recipe.json must be valid JSON with a 'facets' list of facet names"));
        deployer.build("{}", admin);
    }

    function test_run_refusesAChainThatIsNotHedera() public {
        vm.expectRevert(
            bytes(
                "DeployDiamond: this diamond needs Hedera (HTS and a Chainlink feed). Deploy with --network hedera_testnet"
            )
        );
        deployer.run();
    }

    function test_registerHbarUsdFeed_registersTheChainlinkFeedUnderTheSalesKey() public {
        vm.etch(HBAR_USD_FEED_TESTNET, address(new MockAggregatorV3()).code);
        address diamond = deployer.assemble(recipe, address(deployer));

        deployer.registerHbarUsdFeed(diamond);

        (address feed, uint48 maxStaleness) = IChainlinkAdapter(diamond).getFeed("HBAR/USD");
        assertEq(feed, HBAR_USD_FEED_TESTNET);
        // 365 days on testnet, unless your .env sets HBAR_USD_MAX_STALENESS.
        assertEq(maxStaleness, vm.envOr("HBAR_USD_MAX_STALENESS", uint256(365 days)));
    }

    /// @dev Initializes a diamond from one `build`, so the returned cuts are the ones the diamond was made from.
    function _diamond(string memory json)
        internal
        returns (address diamond, string[] memory names, FacetCut[] memory cuts)
    {
        address[] memory inits;
        bytes[] memory calls;
        (names, cuts, inits, calls) = deployer.build(json, admin);
        Lattice lattice = new Lattice();
        lattice.initialize(cuts, address(new MultiInit()), abi.encodeCall(MultiInit.multiInit, (inits, calls)));
        diamond = address(lattice);
    }
}
