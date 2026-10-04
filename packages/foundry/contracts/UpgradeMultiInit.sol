// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { MultiInit } from "@diamond/initializers/MultiInit.sol";
import { InitializableLib } from "@lattice/utils/libraries/InitializableLib.sol";

/// @title UpgradeMultiInit
/// @notice Runs Lattice initializers from a `diamondCut` on a diamond that already exists. A Lattice initializer
///         only runs inside the diamond's initializing window, which closed when the diamond was created, so
///         this opens the next reinitializer version around `MultiInit`'s loop. The diamond delegatecalls it.
contract UpgradeMultiInit is MultiInit {
    function upgradeInit(address[] calldata inits, bytes[] calldata calls) external {
        bytes32 slot = InitializableLib.initializableSlot();
        uint64 version = InitializableLib.getInitializedVersion(slot) + 1;
        InitializableLib.preReinitializer(slot, version);
        multiInit(inits, calls);
        InitializableLib.postReinitializer(slot, version);
    }
}
