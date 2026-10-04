// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TokenSaleV2 } from "../contracts/TokenSaleV2.sol";
import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";

/// @title DeployTokenSaleV2
/// @notice Deploys the TokenSaleV2 facet on its own. It changes nothing until the diamond's admin cuts it
///         in, which the app's Diamond page does (see the README's upgrade walkthrough).
/// @dev Records the facet in `deployments/<chainId>.json`, not in the diamond's record, so the app's `Diamond`
///      ABI does not gain `bonusBps()`.
contract DeployTokenSaleV2 is ScaffoldETHDeploy {
    /// @notice Deploys the facet from the broadcasting account and records its address.
    function run() external ScaffoldEthDeployerRunner {
        TokenSaleV2 facet = new TokenSaleV2();
        deployments.push(Deployment({ name: "TokenSaleV2", addr: address(facet) }));
    }
}
