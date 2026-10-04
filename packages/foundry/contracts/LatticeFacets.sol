// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// The facets (and inits) this project can deploy by name. One import line wires one more.
// `DeployDiamond` stops unless `out/<Name>.sol/<Name>.json` exists for each recipe facet and init, and Foundry
// writes it only for what is imported here.
import { DiamondLoupeFacet } from "@diamond/facets/DiamondLoupeFacet.sol";
import { ERC165Facet } from "@diamond/facets/ERC165Facet.sol";
import { Receive } from "@lattice/Receive.sol";
import { AccessControl } from "@lattice/access/AccessControl.sol";
import { AccessControlInit } from "@lattice/access/AccessControlInit.sol";
import { AccessControlDiamondCut } from "@lattice/governance/AccessControlDiamondCut.sol";
import { ChainlinkAdapter } from "@lattice/oracles/chainlink/ChainlinkAdapter.sol";
import { ChainlinkAdapterInit } from "@lattice/oracles/chainlink/ChainlinkAdapterInit.sol";
import { PythAdapter } from "@lattice/oracles/pyth/PythAdapter.sol";
import { PythAdapterInit } from "@lattice/oracles/pyth/PythAdapterInit.sol";
import { ERC5564Announcer } from "@lattice/privacy/ERC5564Announcer.sol";
import { ERC5564AnnouncerInit } from "@lattice/privacy/ERC5564AnnouncerInit.sol";
import { ERC6538Registry } from "@lattice/privacy/ERC6538Registry.sol";
import { ERC6538RegistryInit } from "@lattice/privacy/ERC6538RegistryInit.sol";
import { EmergencyStop } from "@lattice/security/EmergencyStop.sol";
import { Pausable } from "@lattice/security/Pausable.sol";
import { HTSAdapter } from "@lattice/tokens/hedera/HTSAdapter.sol";
import { HTSAdapterInit } from "@lattice/tokens/hedera/HTSAdapterInit.sol";
import { Multicall } from "@lattice/utils/Multicall.sol";
