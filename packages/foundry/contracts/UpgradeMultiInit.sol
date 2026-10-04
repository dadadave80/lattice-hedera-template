// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { MultiInit } from "@diamond/initializers/MultiInit.sol";
import { InitializableLib } from "@lattice/utils/libraries/InitializableLib.sol";

/// @title UpgradeMultiInit
/// @notice Runs Lattice initializers from a `diamondCut` on a diamond that already exists. A Lattice initializer
///         only runs inside the diamond's initializing window, which closed when the diamond was created, so
///         this opens the next reinitializer version around `MultiInit`'s loop. The diamond delegatecalls it.
/// @dev Pass it as `diamondCut`'s `_init`, so it runs with the cut's access control (`DEFAULT_ADMIN_ROLE` on
///      `AccessControlDiamondCut`). Called directly, it only touches its own storage.
contract UpgradeMultiInit is MultiInit {
    /// @notice Runs each `inits[i]` with `calls[i]` by delegatecall, inside a fresh initializing window.
    /// @dev Raises the diamond's initialized version by one each run. Reverts with `InvalidInitialization` if
    ///      the diamond is already initializing.
    /// @param inits The initializer contracts, in the order they run.
    /// @param calls The calldata for each initializer, matched by index.
    function upgradeInit(address[] calldata inits, bytes[] calldata calls) external {
        bytes32 slot = InitializableLib.initializableSlot();
        uint64 version = InitializableLib.getInitializedVersion(slot) + 1;
        InitializableLib.preReinitializer(slot, version);
        multiInit(inits, calls);
        InitializableLib.postReinitializer(slot, version);
    }
}
