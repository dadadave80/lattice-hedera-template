// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TokenSaleV2 } from "../contracts/TokenSaleV2.sol";
import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";

/// @notice Deploys the TokenSaleV2 facet on its own. It changes nothing until the diamond's admin cuts it
///         in, which the app's Diamond page does (see the README's upgrade walkthrough).
contract DeployTokenSaleV2 is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        TokenSaleV2 facet = new TokenSaleV2();
        deployments.push(Deployment({ name: "TokenSaleV2", addr: address(facet) }));
    }
}
