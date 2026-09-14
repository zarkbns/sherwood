// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "./Ownable.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";

/// @title ProtectionOracle
/// @notice Thin validation wrapper around Chainlink feeds. Returns prices only after
///         round-completeness, freshness, and — when the chain publishes one — L2
///         sequencer-uptime checks. No caching, no fallbacks, no user-supplied values.
contract ProtectionOracle is Ownable {
    /// @notice Chainlink's L2 sequencer uptime feed, or address(0) on a chain that
    ///         publishes none (Robinhood Chain testnet 46630 today). Address(0) means
    ///         the check is skipped and the per-asset staleness guard stands alone.
    IAggregatorV3 public sequencerUptimeFeed;

    /// @notice Seconds to wait after the sequencer restarts before trusting prices
    ///         again. Robinhood Chain and Arbitrum both recommend 30-60 minutes.
    uint256 public sequencerGracePeriod;

    /// @notice Owner cap on the grace period, so a fat-fingered value cannot disable the
    ///         check in practice by pushing it a year out.
    uint256 public constant MAX_SEQUENCER_GRACE_PERIOD = 1 days;

    event SequencerUptimeFeedSet(address indexed feed);
    event SequencerGracePeriodSet(uint256 gracePeriod);

    error SequencerDown();
    error SequencerGracePeriodNotOver();
    error InvalidSequencerFeed();
    error GracePeriodTooLong();

    /// @param _sequencerUptimeFeed Chainlink L2 uptime feed, or address(0) to skip the
    ///        check. Never hardcoded per chain: script/Deploy.s.sol reads it from
    ///        SEQUENCER_UPTIME_FEED so the verified address is chosen at deploy time.
    /// @param _sequencerGracePeriod Seconds after restart before prices are trusted.
    constructor(IAggregatorV3 _sequencerUptimeFeed, uint256 _sequencerGracePeriod) {
        sequencerUptimeFeed = _sequencerUptimeFeed;
        emit SequencerUptimeFeedSet(address(_sequencerUptimeFeed));
        _setSequencerGracePeriod(_sequencerGracePeriod);
    }

    /// @notice Returns a validated Chainlink price (8 decimals) and its update timestamp.
    function getPrice(IAggregatorV3 feed, uint256 maxStaleness) external view returns (uint256 price, uint256 updatedAt) {
        _requireSequencerUp();

        (uint80 roundId, int256 answer,, uint256 updated, uint80 answeredInRound) = feed.latestRoundData();

        if (answeredInRound < roundId) revert StaleRound();
        if (answer <= 0) revert InvalidPrice();
        if (updated == 0) revert InvalidPrice();
        // A feed stamped ahead of the block clock is not a price we can reason about.
        // Rejected here rather than left to `block.timestamp - updated` underflowing.
        if (updated > block.timestamp) revert InvalidPrice();
        if (block.timestamp - updated > maxStaleness) revert StalePrice();

        return (uint256(answer), updated);
    }

    /// @notice Point the oracle at a chain's uptime feed, or at address(0) to turn the
    ///         check off on a chain without one.
    function setSequencerUptimeFeed(IAggregatorV3 feed) external onlyOwner {
        sequencerUptimeFeed = feed;
        emit SequencerUptimeFeedSet(address(feed));
    }

    function setSequencerGracePeriod(uint256 newGracePeriod) external onlyOwner {
        _setSequencerGracePeriod(newGracePeriod);
    }

    /// @dev Chainlink L2 uptime feeds answer 0 while the sequencer is up and 1 while it
    ///      is down, and report in `startedAt` when the sequencer last came back up.
    ///      Prices are untrustworthy both while it is down and for a grace period after
    ///      it restarts: the update backlog lands in a burst, so the first rounds can
    ///      carry pre-outage prices stamped as fresh.
    function _requireSequencerUp() private view {
        IAggregatorV3 uptimeFeed = sequencerUptimeFeed;
        if (address(uptimeFeed) == address(0)) return; // no feed published on this chain

        (, int256 answer, uint256 startedAt,,) = uptimeFeed.latestRoundData();

        // Anything other than a clean 0 is treated as down. Refusing to price is always
        // the safe direction, so a malformed answer fails closed.
        if (answer != 0) revert SequencerDown();
        if (startedAt == 0 || startedAt > block.timestamp) revert InvalidSequencerFeed();
        if (block.timestamp - startedAt <= sequencerGracePeriod) revert SequencerGracePeriodNotOver();
    }

    function _setSequencerGracePeriod(uint256 newGracePeriod) internal {
        if (newGracePeriod > MAX_SEQUENCER_GRACE_PERIOD) revert GracePeriodTooLong();
        sequencerGracePeriod = newGracePeriod;
        emit SequencerGracePeriodSet(newGracePeriod);
    }

    error StaleRound();
    error InvalidPrice();
    error StalePrice();
}
