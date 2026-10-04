// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IDiamondCut } from "@diamond/interfaces/IDiamondCut.sol";
import { FacetCut } from "@diamond/libraries/DiamondLib.sol";
import { BaseDeploy } from "@lattice-script/base/BaseDeploy.s.sol";
import { ERC5564AnnouncerInit } from "@lattice/privacy/ERC5564AnnouncerInit.sol";
import { ERC6538RegistryInit } from "@lattice/privacy/ERC6538RegistryInit.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { StealthBuy } from "../contracts/StealthBuy.sol";
import { UpgradeMultiInit } from "../contracts/UpgradeMultiInit.sol";

// `_facet` deploys Lattice facets by name from their artifacts, which this import compiles.
import "../contracts/LatticeFacets.sol";

/// @title DeployStealthBuy
/// @notice Adds stealth purchases to a diamond that was deployed without them, such as the reference diamond on
///         Hedera testnet: deploys `StealthBuy`, `ERC6538Registry` and `ERC5564Announcer`, cuts all three in
///         with one `diamondCut` that also runs their initializers, then adds them to the deployment record so
///         `scripts-js/generateTsAbis.js` puts their functions in the app's `Diamond` ABI.
/// @dev The broadcasting account must hold the diamond's `DEFAULT_ADMIN_ROLE`. A diamond deployed from the
///      current recipe already has all three, and this cut would revert.
contract DeployStealthBuy is BaseDeploy {
    function run() external {
        string memory path = string.concat("deployments/diamond/", vm.toString(block.chainid), ".json");
        require(
            vm.exists(path),
            string.concat(
                "DeployStealthBuy: no diamond is recorded in ",
                path,
                ". Deploy one first: yarn foundry:deploy --network hedera_testnet"
            )
        );
        address diamond = vm.parseJsonAddress(vm.readFile(path), ".address");

        vm.startBroadcast();
        (string[] memory names, FacetCut[] memory cuts, address init, bytes memory initCalldata) = plan();
        IDiamondCut(diamond).diamondCut(cuts, init, initCalldata);
        vm.stopBroadcast();

        // A run without --broadcast cuts nothing on chain, so the record must not list the facets yet.
        if (vm.isContext(VmSafe.ForgeContext.ScriptDryRun)) return;
        _addToRecord(path, names, cuts);
        console.log("StealthBuy, ERC6538Registry and ERC5564Announcer cut into", diamond);
    }

    /// @notice Deploys the three facets and their initializers, and returns the `diamondCut` arguments that add
    ///         them. Never broadcasts, so tests call it directly.
    function plan()
        public
        returns (string[] memory names, FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        names = new string[](3);
        cuts = new FacetCut[](3);
        names[0] = "StealthBuy";
        cuts[0] = _cut(address(new StealthBuy()));
        names[1] = "ERC6538Registry";
        cuts[1] = _cut(_facet("ERC6538Registry"));
        names[2] = "ERC5564Announcer";
        cuts[2] = _cut(_facet("ERC5564Announcer"));

        address[] memory inits = new address[](2);
        bytes[] memory calls = new bytes[](2);
        inits[0] = address(new ERC6538RegistryInit());
        calls[0] = abi.encodeCall(ERC6538RegistryInit.init, ());
        inits[1] = address(new ERC5564AnnouncerInit());
        calls[1] = abi.encodeCall(ERC5564AnnouncerInit.init, ());
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
                "stealthSelectors",
                recorded[i],
                vm.parseJsonStringArray(json, string.concat(".selectors.", recorded[i]))
            );
        }
        for (uint256 i; i < names.length; ++i) {
            facets[recorded.length + i] = names[i];
            bytes4[] memory cut = cuts[i].functionSelectors;
            string[] memory hexes = new string[](cut.length);
            for (uint256 j; j < cut.length; ++j) {
                hexes[j] = vm.toString(abi.encodePacked(cut[j]));
            }
            selectors = vm.serializeString("stealthSelectors", names[i], hexes);
        }
        vm.serializeAddress("stealthRecord", "address", vm.parseJsonAddress(json, ".address"));
        vm.serializeUint("stealthRecord", "deployedOnBlock", vm.parseJsonUint(json, ".deployedOnBlock"));
        vm.serializeString("stealthRecord", "facets", facets);
        vm.writeJson(vm.serializeString("stealthRecord", "selectors", selectors), path);
    }
}
