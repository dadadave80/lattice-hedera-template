// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { FacetCut } from "@diamond/libraries/DiamondLib.sol";
import { BaseDeploy } from "@lattice-script/base/BaseDeploy.s.sol";
import { HTSAdapterInit } from "@lattice/tokens/hedera/HTSAdapterInit.sol";
import { DiamondIntrospectionInit } from "@lattice/utils/DiamondIntrospectionInit.sol";

// A facet is deployed by name from its compiled artifact, and Foundry compiles only what something imports.
// Importing the wiring file here makes every wired facet part of any build that includes this script.
import "../contracts/LatticeFacets.sol";

/// @title DeployDiamond
/// @notice Builds this project's diamond in two layers and deploys it in one transaction.
///         - The Lattice base comes from `diamond.recipe.json`, a file in Lattice Studio's recipe format.
///           Change the base by editing that file (or exporting over it from Studio), never by editing cuts here.
///         - The Hedera layer is fixed below: `HTSAdapter`. It stays out of the recipe because Studio's
///           catalog does not carry the Hedera facets yet.
/// @dev `build` and `assemble` take the recipe as a string and never broadcast, so tests call them directly.
contract DeployDiamond is BaseDeploy {
    /// @dev How many facets and initializers the Hedera layer appends to the recipe's.
    uint256 internal constant HEDERA_FACETS = 1;
    uint256 internal constant HEDERA_INITS = 2;

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
            names[i] = base[i];
            cuts[i] = _cut(_facet(base[i]));
        }
        names[base.length] = "HTSAdapter";
        cuts[base.length] = _cut(_facet("HTSAdapter"));

        uint256 steps = _stepCount(json);
        inits = new address[](steps + HEDERA_INITS);
        calls = new bytes[](steps + HEDERA_INITS);
        for (uint256 i; i < steps; ++i) {
            (inits[i], calls[i]) = _initStep(json, i, admin);
        }
        inits[steps] = address(new HTSAdapterInit());
        calls[steps] = abi.encodeCall(HTSAdapterInit.init, (admin));
        inits[steps + 1] = address(new DiamondIntrospectionInit());
        calls[steps + 1] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    // ── recipe reading ──────────────────────────────────────────────────────────────────────────────

    function _facetNames(string memory json) internal pure returns (string[] memory) {
        return vm.parseJsonStringArray(json, ".facets");
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
}
