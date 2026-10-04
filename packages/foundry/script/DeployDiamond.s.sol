// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { FacetCut } from "@diamond/libraries/DiamondLib.sol";
import { BaseDeploy } from "@lattice-script/base/BaseDeploy.s.sol";
import { IChainlinkAdapter } from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
import { HTSAdapterInit } from "@lattice/tokens/hedera/HTSAdapterInit.sol";
import { DiamondIntrospectionInit } from "@lattice/utils/DiamondIntrospectionInit.sol";
import { console } from "forge-std/console.sol";
import { TokenSale } from "../contracts/TokenSale.sol";
import { TokenSaleInit } from "../contracts/TokenSaleInit.sol";

// A facet is deployed by name from its compiled artifact, and Foundry compiles only what something imports.
// Importing the wiring file here makes every wired facet part of any build that includes this script.
import "../contracts/LatticeFacets.sol";

/// @title DeployDiamond
/// @notice Builds this project's diamond in two layers and deploys it in one transaction.
///         - The Lattice base comes from `diamond.recipe.json`, a file in Lattice Studio's recipe format.
///           Change the base by editing that file (or exporting over it from Studio), never by editing cuts here.
///         - The Hedera layer is fixed below: `HTSAdapter` and this project's `TokenSale` facet. It stays out
///           of the recipe because Studio's catalog does not carry the Hedera facets yet.
/// @dev `build` and `assemble` take the recipe as a string and never broadcast, so tests call them directly.
contract DeployDiamond is BaseDeploy {
    string internal constant RECIPE = "diamond.recipe.json";

    /// @dev The key the sale reads its HBAR/USD rate under, on whichever oracle facet the recipe cuts.
    bytes32 internal constant HBAR_USD = "HBAR/USD";

    /// @dev Chainlink HBAR/USD price feeds (https://docs.chain.link/data-feeds/price-feeds/addresses?network=hedera).
    address internal constant HBAR_USD_FEED_TESTNET = 0x59bC155EB6c6C415fE43255aF66EcF0523c92B4a;
    address internal constant HBAR_USD_FEED_MAINNET = 0xAF685FB45C12b92b5054ccb9313e135525F9b5d5;

    /// @dev How many facets and initializers the Hedera layer appends to the recipe's.
    uint256 internal constant HEDERA_FACETS = 2;
    uint256 internal constant HEDERA_INITS = 3;

    function run() external returns (address diamond) {
        require(
            block.chainid == 295 || block.chainid == 296,
            "DeployDiamond: this diamond needs Hedera (HTS and a Chainlink feed). Deploy with --network hedera_testnet"
        );
        string memory json = vm.readFile(RECIPE);

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        diamond = assemble(json, deployer);
        _registerHbarUsdFeed(diamond);
        vm.stopBroadcast();

        console.log("Diamond deployed at", diamond);
    }

    /// @notice Deploys the diamond described by `json` plus the Hedera layer, with `admin` holding every role.
    function assemble(string memory json, address admin) public returns (address diamond) {
        (, FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls) = build(json, admin);
        diamond = _assembleMulti(cuts, inits, calls);
    }

    /// @notice The facet cuts and initializer calls for the recipe's base plus the Hedera layer.
    /// @return names The facet name behind each cut, in cut order.
    function build(string memory json, address admin)
        public
        returns (string[] memory names, FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls)
    {
        string[] memory base = _facetNames(json);
        names = new string[](base.length + HEDERA_FACETS);
        cuts = new FacetCut[](base.length + HEDERA_FACETS);
        for (uint256 i; i < base.length; ++i) {
            _requireWired(base[i]);
            names[i] = base[i];
            cuts[i] = _cut(_facet(base[i]));
        }
        names[base.length] = "HTSAdapter";
        cuts[base.length] = _cut(_facet("HTSAdapter"));
        names[base.length + 1] = "TokenSale";
        cuts[base.length + 1] = _cut(address(new TokenSale()));

        uint256 steps = _stepCount(json);
        inits = new address[](steps + HEDERA_INITS);
        calls = new bytes[](steps + HEDERA_INITS);
        for (uint256 i; i < steps; ++i) {
            (inits[i], calls[i]) = _initStep(json, i, admin);
        }
        inits[steps] = address(new HTSAdapterInit());
        calls[steps] = abi.encodeCall(HTSAdapterInit.init, (admin));
        inits[steps + 1] = address(new TokenSaleInit());
        calls[steps + 1] = abi.encodeCall(TokenSaleInit.init, (HBAR_USD));
        inits[steps + 2] = address(new DiamondIntrospectionInit());
        calls[steps + 2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    // ── recipe reading ──────────────────────────────────────────────────────────────────────────────

    function _facetNames(string memory json) internal pure returns (string[] memory) {
        try vm.parseJsonStringArray(json, ".facets") returns (string[] memory names) {
            return names;
        } catch {
            revert("Recipe: diamond.recipe.json must be valid JSON with a 'facets' list of facet names");
        }
    }

    function _stepCount(string memory json) internal view returns (uint256 n) {
        while (vm.keyExistsJson(json, string.concat(".init.steps[", vm.toString(n), "]"))) {
            ++n;
        }
    }

    /// @dev Every initializer the recipe lists is called as `init(admin)`.
    function _initStep(string memory json, uint256 i, address admin)
        internal
        returns (address init, bytes memory data)
    {
        string memory spec = vm.parseJsonString(json, string.concat(".init.steps[", vm.toString(i), "].spec"));
        init = deployCode(string.concat(spec, ".sol:", spec));
        data = abi.encodeWithSignature("init(address)", admin);
    }

    /// @dev A facet can only be deployed by name if `contracts/LatticeFacets.sol` compiled it into this project.
    function _requireWired(string memory name) internal view {
        require(
            vm.exists(string.concat("out/", name, ".sol/", name, ".json")),
            string.concat(
                "Recipe: ",
                name,
                " is in the recipe but not compiled into this project; add its import to contracts/LatticeFacets.sol"
            )
        );
    }

    // ── after the diamond exists ────────────────────────────────────────────────────────────────────

    /// @dev Chainlink only. Another oracle facet registers its feed with its own arguments (see the README).
    function _registerHbarUsdFeed(address diamond) internal {
        if (IDiamondLoupe(diamond).facetAddress(IChainlinkAdapter.registerFeed.selector) == address(0)) {
            console.log(
                "No ChainlinkAdapter in this recipe: register an HBAR/USD feed under the key 'HBAR/USD' yourself."
            );
            return;
        }
        bool mainnet = block.chainid == 295;
        // Testnet feeds are not kept on a production heartbeat, so the testnet default is deliberately loose.
        uint256 maxStaleness = vm.envOr("HBAR_USD_MAX_STALENESS", mainnet ? uint256(25 hours) : uint256(365 days));
        IChainlinkAdapter(diamond)
            .registerFeed(HBAR_USD, mainnet ? HBAR_USD_FEED_MAINNET : HBAR_USD_FEED_TESTNET, uint48(maxStaleness));
    }
}
