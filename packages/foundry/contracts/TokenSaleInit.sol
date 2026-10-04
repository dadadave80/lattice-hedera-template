// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TokenSaleLib } from "./libraries/TokenSaleLib.sol";

/// @title TokenSaleInit
/// @notice Initializer for the TokenSale facet. The diamond delegatecalls it once, while it is being created.
/// @dev Writes to the storage of whoever delegatecalls it. It reverts with `NotInitializing` unless that
///      storage's initializing window is open: while the diamond is created, or inside `UpgradeMultiInit`.
contract TokenSaleInit {
    /// @notice Stores the key the sale reads its HBAR/USD rate under.
    /// @param feedKey The key the sale passes to the diamond's `latestAnswer(bytes32)` for the HBAR/USD rate.
    function init(bytes32 feedKey) external {
        TokenSaleLib.__TokenSale_init(feedKey);
    }
}
