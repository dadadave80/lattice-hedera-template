// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { MultiInit } from "@diamond/initializers/MultiInit.sol";
import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { Facet, FacetCut } from "@diamond/libraries/DiamondLib.sol";
import { Lattice } from "@lattice/Lattice.sol";
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
import { IChainlinkAdapter } from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
import { IPythAdapter } from "@lattice/interfaces/oracles/IPythAdapter.sol";
import { IERC5564Announcer } from "@lattice/interfaces/privacy/IERC5564Announcer.sol";
import { IERC6538Registry } from "@lattice/interfaces/privacy/IERC6538Registry.sol";
import { IHTSAdapter } from "@lattice/interfaces/tokens/IHTSAdapter.sol";
import { Test } from "forge-std/Test.sol";
import { IERC165 } from "forge-std/interfaces/IERC165.sol";
import { ISaucerSwapPool } from "../contracts/interfaces/ISaucerSwapPool.sol";
import { IStealthBuy } from "../contracts/interfaces/IStealthBuy.sol";
import { ITokenSale } from "../contracts/interfaces/ITokenSale.sol";
import { DeployDiamond } from "../script/DeployDiamond.s.sol";
import { MockAggregatorV3 } from "./mocks/MockAggregatorV3.sol";

/// @dev Opens the two steps `run()` performs after the diamond exists, so they can be tested without a broadcast.
contract DeployDiamondHarness is DeployDiamond {
    function registerHbarUsdFeed(address diamond) external {
        _registerHbarUsdFeed(diamond, address(this));
    }

    function writeRecord(address diamond, string[] memory names, FacetCut[] memory cuts) external {
        _writeRecord(diamond, names, cuts);
    }
}

contract DeployDiamondTest is Test {
    bytes4 internal constant LATEST_ANSWER = 0x084d4783;
    bytes4 internal constant UNREGISTER_FEED = 0x2a589908;
    address internal constant HBAR_USD_FEED_TESTNET = 0x59bC155EB6c6C415fE43255aF66EcF0523c92B4a;
    string internal constant MISSING_HTS_ADAPTER =
        "Recipe: TokenSale creates its token through HTSAdapter, with the roles HTSAdapterInit grants; add HTSAdapter and its HTSAdapterInit step in Lattice Studio";
    /// @dev A chain no developer deploys to, so the record these tests write never replaces a real one.
    uint256 internal constant RECORD_CHAIN = 2_960_000_003;

    address internal admin = makeAddr("admin");
    DeployDiamondHarness internal deployer;
    string internal recipe;

    function setUp() public {
        deployer = new DeployDiamondHarness();
        recipe = vm.readFile("test/fixtures/default.recipe.json");
    }

    /// @dev The one test that reads your own `diamond.recipe.json`. It stays green as long as that file builds, and
    ///      checks only what the deploy itself requires.
    function test_projectRecipe_buildsADiamondWithTheHederaLayer() public {
        (address diamond,,) = _diamond(vm.readFile("diamond.recipe.json"));
        assertTrue(IDiamondLoupe(diamond).facetAddress(ITokenSale.saleInfo.selector) != address(0), "TokenSale");
        assertTrue(IDiamondLoupe(diamond).facetAddress(IStealthBuy.buyFor.selector) != address(0), "StealthBuy");
        assertTrue(
            IDiamondLoupe(diamond).facetAddress(ISaucerSwapPool.seedPool.selector) != address(0), "SaucerSwapPool"
        );
        assertTrue(
            IDiamondLoupe(diamond).facetAddress(IHTSAdapter.createFungibleToken.selector) != address(0), "HTSAdapter"
        );
    }

    function test_defaultRecipe_buildsTheBaseAndTheHederaLayer() public {
        (address diamond, string[] memory names, FacetCut[] memory cuts) = _diamond(recipe);
        string[] memory base = vm.parseJsonStringArray(recipe, ".facets");

        assertEq(base.length, 10, "ten base facets, HTSAdapter and the stealth pair among them");
        for (uint256 i; i < base.length; ++i) {
            assertEq(names[i], base[i], "the recipe's facets come first, in its order");
        }
        assertEq(names[1], "HTSAdapter");
        assertEq(names[2], "ERC5564Announcer");
        assertEq(names[3], "ERC6538Registry");
        assertGe(_indexOf(names, "TokenSale"), base.length, "TokenSale comes after the base");
        assertGe(_indexOf(names, "StealthBuy"), base.length, "StealthBuy comes after the base");
        assertGe(_indexOf(names, "SaucerSwapPool"), base.length, "SaucerSwapPool comes after the base");

        Facet[] memory facets = IDiamondLoupe(diamond).facets();
        assertEq(facets.length, names.length, "every cut is a facet of the diamond");

        uint256 baseSelectors;
        for (uint256 i; i < cuts.length; ++i) {
            if (i < base.length) baseSelectors += cuts[i].functionSelectors.length;
            for (uint256 j; j < cuts[i].functionSelectors.length; ++j) {
                assertEq(
                    IDiamondLoupe(diamond).facetAddress(cuts[i].functionSelectors[j]),
                    cuts[i].facetAddress,
                    string.concat("a ", names[i], " selector is routed elsewhere")
                );
            }
        }
        assertEq(baseSelectors, 45, "the selector count Lattice Studio plans for the default base");
    }

    function test_defaultRecipe_runsTheInitStepsThatTakeNoArguments() public {
        (address diamond,,) = _diamond(recipe);

        assertTrue(
            IERC165(diamond).supportsInterface(type(IERC6538Registry).interfaceId), "ERC6538RegistryInit registered it"
        );
        assertTrue(
            IERC165(diamond).supportsInterface(type(IERC5564Announcer).interfaceId),
            "ERC5564AnnouncerInit registered it"
        );
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
            ),
            "ERC6538RegistryInit set the EIP-712 domain ERC-6538 signers expect"
        );
    }

    function test_defaultRecipe_makesTheAdminTheAdminOfEveryLayer() public {
        (address diamond,,) = _diamond(recipe);

        assertTrue(IAccessControl(diamond).hasRole(bytes32(0), admin), "DEFAULT_ADMIN_ROLE");
        assertTrue(IAccessControl(diamond).hasRole(keccak256("HTS_MANAGER_ROLE"), admin), "HTS_MANAGER_ROLE");
        (,,, bytes32 feedKey,,) = ITokenSale(diamond).saleInfo();
        assertEq(feedKey, bytes32("HBAR/USD"), "TokenSaleInit ran");
    }

    function test_oracleSwap_routesLatestAnswerToThePythFacet() public {
        (address diamond,, FacetCut[] memory cuts) = _diamond(vm.readFile("test/fixtures/pyth.recipe.json"));

        address pythFacet = cuts[0].facetAddress; // PythAdapter is first in the fixture
        assertEq(IDiamondLoupe(diamond).facetAddress(LATEST_ANSWER), pythFacet);
        assertEq(IDiamondLoupe(diamond).facetAddress(IPythAdapter.updatePriceFeeds.selector), pythFacet);
        assertEq(IPythAdapter(diamond).pyth(), 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729, "PythAdapterInit ran");
    }

    function test_owners_routeAContestedSelectorToItsOwner() public {
        (address diamond,, FacetCut[] memory cuts) = _diamond(vm.readFile("test/fixtures/both-oracles.recipe.json"));

        // The fixture lists ChainlinkAdapter then PythAdapter, and gives the four shared selectors to Pyth.
        assertEq(cuts[0].functionSelectors.length, 1, "Chainlink keeps only its own registerFeed");
        assertEq(cuts[0].functionSelectors[0], IChainlinkAdapter.registerFeed.selector);
        assertEq(IDiamondLoupe(diamond).facetAddress(LATEST_ANSWER), cuts[1].facetAddress);
    }

    function test_exclude_leavesTheSelectorOutOfTheDiamond() public {
        string memory json = vm.readFile("test/fixtures/more-facets.recipe.json");
        (address diamond, string[] memory names,) = _diamond(json);

        assertEq(vm.parseJsonStringArray(json, ".facets").length, 12, "twelve base facets");
        assertEq(IDiamondLoupe(diamond).facets().length, names.length, "the facet that lost a selector is still cut");
        assertEq(IDiamondLoupe(diamond).facetAddress(UNREGISTER_FEED), address(0));
        assertTrue(IDiamondLoupe(diamond).facetAddress(LATEST_ANSWER) != address(0));
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

    function test_build_revertsWhenTwoFacetsExportTheSameSelector() public {
        string memory json = vm.replace(recipe, '"ChainlinkAdapter",', '"ChainlinkAdapter", "PythAdapter",');

        vm.expectRevert(
            bytes(
                "Recipe: selector 0x280aebcf is exported by both ChainlinkAdapter and PythAdapter; give it one owner in Lattice Studio (owners) or drop it (exclude)"
            )
        );
        deployer.build(json, admin);
    }

    function test_build_revertsOnABundleInit() public {
        string memory json = vm.replace(recipe, '"kind": "steps"', '"kind": "bundle"');

        vm.expectRevert(bytes("Recipe: init.kind must be 'steps' or 'none'; 'bundle' inits are not supported yet"));
        deployer.build(json, admin);
    }

    function test_build_revertsOnASelfReference() public {
        string memory json = vm.replace(recipe, '"$ref": "deployer"', '"$ref": "self"');

        vm.expectRevert(bytes('Recipe: only {"$ref": "deployer"} is supported; {"$ref": "self"} is not yet'));
        deployer.build(json, admin);
    }

    function test_build_revertsOnAnInitItCannotEncode() public {
        string memory json = vm.replace(
            recipe,
            '"spec": "ChainlinkAdapterInit",\n        "args": {',
            '"spec": "ChainlinkAdapterInit",\n        "args": {\n          "extra": "0x0000000000000000000000000000000000000001",'
        );

        vm.expectRevert(
            bytes(
                "Recipe: ChainlinkAdapterInit takes arguments this template cannot encode yet; add an encoder in _initStep"
            )
        );
        deployer.build(json, admin);
    }

    function test_build_revertsOnAFileThatIsNotARecipe() public {
        vm.expectRevert(bytes("Recipe: diamond.recipe.json must be valid JSON with a 'facets' list of facet names"));
        deployer.build("{}", admin);
    }

    function test_build_revertsWhenTheRecipeLacksHTSAdapter() public {
        string memory json = vm.replace(recipe, '"HTSAdapter",', "");

        vm.expectRevert(bytes(MISSING_HTS_ADAPTER));
        deployer.build(json, admin);
    }

    function test_build_revertsWhenNoStepInitializesHTSAdapter() public {
        // With no init steps, nothing grants the roles TokenSale needs to create its token.
        string memory json =
            vm.replace(vm.readFile("test/fixtures/pyth.recipe.json"), '"kind": "steps"', '"kind": "none"');

        vm.expectRevert(bytes(MISSING_HTS_ADAPTER));
        deployer.build(json, admin);
    }

    function test_warnings_areEmptyForTheDefaultRecipe() public {
        (, FacetCut[] memory cuts,,) = deployer.build(recipe, admin);

        assertEq(deployer.warnings(recipe, cuts).length, 0);
    }

    function test_warnings_flagAnotherCatalogAndAMissingCutFacet() public {
        string memory json = vm.replace(recipe, '"dev-6c8db45"', '"v9.9.9"');
        json = vm.replace(json, '"AccessControlDiamondCut",', "");
        (, FacetCut[] memory cuts,,) = deployer.build(json, admin);

        string[] memory notes = deployer.warnings(json, cuts);

        assertEq(notes.length, 2);
        assertEq(notes[0], "the recipe is pinned to catalog v9.9.9 but this template's Lattice matches dev-6c8db45");
        assertEq(notes[1], "no facet in the recipe serves diamondCut, so this diamond cannot be upgraded");
    }

    function test_run_refusesAChainThatIsNotHedera() public {
        vm.chainId(31337); // a fork run starts on Hedera's chain ID
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

    function test_registerHbarUsdFeed_leavesTheFeedToARecipeAdminThatIsNotTheDeployer() public {
        address safe = makeAddr("safe");
        string memory json = vm.replace(
            recipe, '{\n            "$ref": "deployer"\n          }', string.concat('"', vm.toString(safe), '"')
        );
        address diamond = deployer.assemble(json, address(deployer));

        deployer.registerHbarUsdFeed(diamond); // must not revert

        (address feed,) = IChainlinkAdapter(diamond).getFeed("HBAR/USD");
        assertEq(feed, address(0));
        assertFalse(IAccessControl(diamond).hasRole(bytes32(0), address(deployer)), "the deployer is not admin");
        assertTrue(IAccessControl(diamond).hasRole(bytes32(0), safe), "the recipe's admin can register it");
    }

    function test_registerHbarUsdFeed_registersWhenAnyInitMadeTheDeployerAdmin() public {
        vm.etch(HBAR_USD_FEED_TESTNET, address(new MockAggregatorV3()).code);
        address safe = makeAddr("safe");
        // ChainlinkAdapterInit names another admin; HTSAdapterInit still makes the deployer admin.
        string memory json = vm.replace(
            recipe,
            '"spec": "ChainlinkAdapterInit",\n        "args": {\n          "admin": {\n            "$ref": "deployer"\n          }',
            string.concat(
                '"spec": "ChainlinkAdapterInit",\n        "args": {\n          "admin": "', vm.toString(safe), '"'
            )
        );
        address diamond = deployer.assemble(json, address(deployer));
        assertTrue(IAccessControl(diamond).hasRole(bytes32(0), safe), "ChainlinkAdapterInit named the other admin");

        deployer.registerHbarUsdFeed(diamond);

        (address feed,) = IChainlinkAdapter(diamond).getFeed("HBAR/USD");
        assertEq(feed, HBAR_USD_FEED_TESTNET);
    }

    function test_registerHbarUsdFeed_skipsADiamondWithoutChainlink() public {
        address diamond = deployer.assemble(vm.readFile("test/fixtures/pyth.recipe.json"), address(deployer));

        deployer.registerHbarUsdFeed(diamond); // must not revert

        (bytes32 priceId,,) = IPythAdapter(diamond).getFeed("HBAR/USD");
        assertEq(priceId, bytes32(0));
    }

    function test_writeRecord_savesWhatTheFrontendNeeds() public {
        (address diamond, string[] memory names, FacetCut[] memory cuts) = _diamond(recipe);
        vm.chainId(RECORD_CHAIN);
        string memory path = string.concat("deployments/diamond/", vm.toString(block.chainid), ".json");

        deployer.writeRecord(diamond, names, cuts);
        string memory record = vm.readFile(path);
        vm.removeFile(path);

        assertEq(vm.parseJsonAddress(record, ".address"), diamond);
        assertEq(vm.parseJsonUint(record, ".deployedOnBlock"), block.number);
        assertEq(vm.parseJsonStringArray(record, ".facets"), names);
        string[] memory htsSelectors = vm.parseJsonStringArray(record, ".selectors.HTSAdapter");
        assertEq(htsSelectors.length, 13);
        assertEq(htsSelectors[0], vm.toString(abi.encodePacked(IHTSAdapter.associateToken.selector)));
        assertEq(vm.parseJsonStringArray(record, ".selectors.TokenSale").length, 6);
        string[] memory stealthSelectors = vm.parseJsonStringArray(record, ".selectors.StealthBuy");
        assertEq(stealthSelectors.length, 1);
        assertEq(stealthSelectors[0], vm.toString(abi.encodePacked(IStealthBuy.buyFor.selector)));
        assertEq(vm.parseJsonStringArray(record, ".selectors.SaucerSwapPool").length, 3);
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

    function _indexOf(string[] memory names, string memory name) internal pure returns (uint256) {
        for (uint256 i; i < names.length; ++i) {
            if (keccak256(bytes(names[i])) == keccak256(bytes(name))) return i;
        }
        revert(string.concat(name, " is not among the cuts"));
    }
}
