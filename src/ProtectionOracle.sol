// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";

/// @title ProtectionOracle
/// @notice Thin validation wrapper around Chainlink feeds. Returns prices only
///         after round-completeness and freshness checks. No caching, no fallbacks,
///         no user-supplied values ever.
contract ProtectionOracle {
    /// @notice Returns a validated Chainlink price (8 decimals) and its update timestamp.
    function getPrice(IAggregatorV3 feed, uint256 maxStaleness) external view returns (uint256 price, uint256 updatedAt) {
        (uint80 roundId, int256 answer,, uint256 updated, uint80 answeredInRound) = feed.latestRoundData();

        if (answeredInRound < roundId) revert StaleRound();
        if (answer <= 0) revert InvalidPrice();
        if (updated == 0) revert InvalidPrice();
        if (block.timestamp - updated > maxStaleness) revert StalePrice();

        return (uint256(answer), updated);
    }

    error StaleRound();
    error InvalidPrice();
    error StalePrice();
}
