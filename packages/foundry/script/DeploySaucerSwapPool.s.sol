// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IDiamondCut } from "@diamond/interfaces/IDiamondCut.sol";
import { FacetCut } from "@diamond/libraries/DiamondLib.sol";
import { BaseDeploy } from "@lattice-script/base/BaseDeploy.s.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { SaucerSwapPool } from "../contracts/SaucerSwapPool.sol";
import { SaucerSwapPoolInit } from "../contracts/SaucerSwapPoolInit.sol";
import { UpgradeMultiInit } from "../contracts/UpgradeMultiInit.sol";
import { SaucerSwapV1 } from "./DeployDiamond.s.sol";

/// @title DeploySaucerSwapPool
/// @notice Adds SaucerSwap pooling to a diamond that was deployed without it, such as the reference diamond on
///         Hedera testnet: deploys `SaucerSwapPool` and cuts it in with one `diamondCut` that also runs
///         `SaucerSwapPoolInit` with the chain's SaucerSwap V1 addresses, then adds the facet to the deployment
///         record so `scripts-js/generateTsAbis.js` puts its functions in the app's `Diamond` ABI.
/// @dev The broadcasting account must hold the diamond's `DEFAULT_ADMIN_ROLE`. A diamond deployed by the current
///      `DeployDiamond` already has the facet, and this cut would revert.
contract DeploySaucerSwapPool is BaseDeploy {
    function run() external {
        string memory path = string.concat("deployments/diamond/", vm.toString(block.chainid), ".json");
        require(
            vm.exists(path),
            string.concat(
                "DeploySaucerSwapPool: no diamond is recorded in ",
                path,
                ". Deploy one first: yarn foundry:deploy --network hedera_testnet"
            )
        );
        address diamond = vm.parseJsonAddress(vm.readFile(path), ".address");

        vm.startBroadcast();
        (string[] memory names, FacetCut[] memory cuts, address init, bytes memory initCalldata) = plan();
        IDiamondCut(diamond).diamondCut(cuts, init, initCalldata);
        vm.stopBroadcast();

        // A run without --broadcast cuts nothing on chain, so the record must not list the facet yet.
        if (vm.isContext(VmSafe.ForgeContext.ScriptDryRun)) return;
        _addToRecord(path, names, cuts);
        console.log("SaucerSwapPool cut into", diamond);
    }

    /// @notice Deploys the facet and its initializer, and returns the `diamondCut` arguments that add the facet and
    ///         give it this chain's SaucerSwap V1 addresses. Never broadcasts, so tests call it directly.
    function plan()
        public
        returns (string[] memory names, FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        names = new string[](1);
        cuts = new FacetCut[](1);
        names[0] = "SaucerSwapPool";
        cuts[0] = _cut(address(new SaucerSwapPool()));

        (address router, address factory, address whbar) = SaucerSwapV1.addresses(block.chainid);
        address[] memory inits = new address[](1);
        bytes[] memory calls = new bytes[](1);
        inits[0] = address(new SaucerSwapPoolInit());
        calls[0] = abi.encodeCall(SaucerSwapPoolInit.init, (router, factory, whbar));
        init = address(new UpgradeMultiInit());
        initCalldata = abi.encodeCall(UpgradeMultiInit.upgradeInit, (inits, calls));
    }

    /// @dev Rewrites the record `DeployDiamond` wrote with `names` and their selectors after the facets it lists.
    function _addToRecord(string memory path, string[] memory names, FacetCut[] memory cuts) internal {
        string memory json = vm.readFile(path);
        string[] memory recorded = vm.parseJsonStringArray(json, ".facets");
        string[] memory facets = new string[](recorded.length + names.length);
        string memory selectors;
        for (uint256 i; i < recorded.length; ++i) {
            facets[i] = recorded[i];
            selectors = vm.serializeString(
                "poolSelectors", recorded[i], vm.parseJsonStringArray(json, string.concat(".selectors.", recorded[i]))
            );
        }
        for (uint256 i; i < names.length; ++i) {
            facets[recorded.length + i] = names[i];
            bytes4[] memory cut = cuts[i].functionSelectors;
            string[] memory hexes = new string[](cut.length);
            for (uint256 j; j < cut.length; ++j) {
                hexes[j] = vm.toString(abi.encodePacked(cut[j]));
            }
            selectors = vm.serializeString("poolSelectors", names[i], hexes);
        }
        vm.serializeAddress("poolRecord", "address", vm.parseJsonAddress(json, ".address"));
        vm.serializeUint("poolRecord", "deployedOnBlock", vm.parseJsonUint(json, ".deployedOnBlock"));
        vm.serializeString("poolRecord", "facets", facets);
        vm.writeJson(vm.serializeString("poolRecord", "selectors", selectors), path);
    }
}
