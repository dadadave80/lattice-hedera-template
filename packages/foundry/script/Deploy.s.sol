// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { DeployDiamond } from "./DeployDiamond.s.sol";

/// @notice What `yarn foundry:deploy` runs when no `--file` is given: the recipe-driven diamond deploy.
contract DeployScript is DeployDiamond { }
