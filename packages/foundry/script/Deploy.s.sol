// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { DeployDiamond } from "./DeployDiamond.s.sol";

/// @title DeployScript
/// @notice What `yarn foundry:deploy` runs when no `--file` is given: the recipe-driven diamond deploy.
/// @dev Everything is inherited from `DeployDiamond`.
contract DeployScript is DeployDiamond { }
