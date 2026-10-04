// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TokenSaleLib } from "./libraries/TokenSaleLib.sol";

/// @title TokenSaleInit
/// @notice Initializer for the TokenSale facet. The diamond delegatecalls it once, while it is being created.
contract TokenSaleInit {
    /// @param feedKey The key the sale passes to the diamond's `latestAnswer(bytes32)` for the HBAR/USD rate.
    function init(bytes32 feedKey) external {
        TokenSaleLib.__TokenSale_init(feedKey);
    }
}
