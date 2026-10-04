// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IAggregatorV3 } from "@lattice/interfaces/external/chainlink/IAggregatorV3.sol";

/// @notice A Chainlink price feed stand-in: 8 decimals, and an answer the test sets.
contract MockAggregatorV3 is IAggregatorV3 {
    int256 internal _answer;
    uint256 internal _updatedAt;

    function setAnswer(int256 answer) external {
        _answer = answer;
        _updatedAt = block.timestamp;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "HBAR / USD";
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, _answer, _updatedAt, _updatedAt, 1);
    }
}
