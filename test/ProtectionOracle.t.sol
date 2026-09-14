// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {Ownable} from "../src/Ownable.sol";
import {ProtectionOracle} from "../src/ProtectionOracle.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {MockAggregator, MockSequencerFeed} from "./Mocks.sol";

contract ProtectionOracleTest is TestBase {
    ProtectionOracle internal oracle;
    MockAggregator internal feed;
    MockSequencerFeed internal uptime;

    uint256 constant MAX_STALENESS = 72 hours;
    uint256 constant GRACE = 1 hours;

    function setUp() public {
        vmWarp(1_700_000_000);
        // Default fixture has no sequencer uptime feed, so the price-only paths behave
        // exactly as they do on Robinhood Chain testnet, which publishes none.
        oracle = new ProtectionOracle(IAggregatorV3(address(0)), GRACE);
        feed = new MockAggregator(8);
        feed.setPrice(100e8);
        uptime = new MockSequencerFeed();
    }

    /// @dev Turns the sequencer check on against the mock uptime feed, reporting the
    ///      sequencer up and long past its restart grace window.
    function _enableSequencerCheck() internal {
        oracle.setSequencerUptimeFeed(uptime);
        uptime.setStatus(0, block.timestamp - GRACE - 1);
    }

    // ------------------------------------------------------------------
    // price validation (check disabled)
    // ------------------------------------------------------------------

    function test_GetPrice_ReturnsValidPrice() public {
        (uint256 price, uint256 updatedAt) = oracle.getPrice(feed, MAX_STALENESS);
        assertEq(price, 100e8, "price mismatch");
        assertEq(updatedAt, block.timestamp, "updatedAt should equal last set");
    }

    function test_GetPrice_FreshWithinStaleness() public {
        vmWarp(block.timestamp + MAX_STALENESS);
        (uint256 price,) = oracle.getPrice(feed, MAX_STALENESS);
        assertEq(price, 100e8, "boundary staleness should pass");
    }

    function test_GetPrice_RevertsWhenTooStale() public {
        vmWarp(block.timestamp + MAX_STALENESS + 1);
        vmExpectRevert(ProtectionOracle.StalePrice.selector);
        oracle.getPrice(feed, MAX_STALENESS);
    }

    function test_GetPrice_RevertsOnIncompleteRound() public {
        feed.setStaleRound();
        vmExpectRevert(ProtectionOracle.StaleRound.selector);
        oracle.getPrice(feed, MAX_STALENESS);
    }

    function test_GetPrice_RevertsOnNegativeAnswer() public {
        feed.setPrice(-100e8);
        vmExpectRevert(ProtectionOracle.InvalidPrice.selector);
        oracle.getPrice(feed, MAX_STALENESS);
    }

    function test_GetPrice_RevertsOnZeroAnswer() public {
        feed.setPrice(0);
        vmExpectRevert(ProtectionOracle.InvalidPrice.selector);
        oracle.getPrice(feed, MAX_STALENESS);
    }

    function test_GetPrice_RevertsOnZeroUpdatedAt() public {
        feed.setUpdatedAt(0);
        vmExpectRevert(ProtectionOracle.InvalidPrice.selector);
        oracle.getPrice(feed, MAX_STALENESS);
    }

    /// @dev A feed stamped ahead of the block clock is unusable, and must fail with a
    ///      named error rather than an arithmetic underflow panic.
    function test_GetPrice_RevertsOnFutureUpdatedAt() public {
        feed.setUpdatedAt(block.timestamp + 1);
        vmExpectRevert(ProtectionOracle.InvalidPrice.selector);
        oracle.getPrice(feed, MAX_STALENESS);
    }

    function test_GetPrice_ZeroStaleness_RequiresCurrentRound() public {
        // maxStaleness 0: only a price stamped at the current block.timestamp passes
        vmWarp(block.timestamp + 1);
        vmExpectRevert(ProtectionOracle.StalePrice.selector);
        oracle.getPrice(feed, 0);

        feed.setPrice(101e8); // re-stamps updatedAt to now
        (uint256 price,) = oracle.getPrice(feed, 0);
        assertEq(price, 101e8, "fresh stamp should pass zero staleness");
    }

    function testFuzz_GetPrice_StalenessBoundary(uint256 elapsed, uint256 maxStaleness) public {
        maxStaleness = bound(maxStaleness, 0, 365 days);
        elapsed = bound(elapsed, 0, 365 days);
        vmWarp(block.timestamp + elapsed);
        if (elapsed > maxStaleness) {
            vmExpectRevert(ProtectionOracle.StalePrice.selector);
            oracle.getPrice(feed, maxStaleness);
        } else {
            (uint256 price,) = oracle.getPrice(feed, maxStaleness);
            assertEq(price, 100e8, "price should pass within staleness");
        }
    }

    // ------------------------------------------------------------------
    // Chainlink L2 sequencer uptime
    // ------------------------------------------------------------------

    function test_SequencerCheck_OffByDefault() public {
        assertEq(address(oracle.sequencerUptimeFeed()), address(0), "no feed configured");
        assertEq(oracle.sequencerGracePeriod(), GRACE, "grace period from constructor");

        // With no feed published there is nothing to consult: prices flow even though
        // the mock uptime feed would say the sequencer is down.
        uptime.setStatus(1, block.timestamp - GRACE - 1);
        (uint256 price,) = oracle.getPrice(feed, MAX_STALENESS);
        assertEq(price, 100e8, "check off should not consult any uptime feed");
    }

    function test_Sequencer_UpPastGrace_PricesFlow() public {
        _enableSequencerCheck();
        (uint256 price,) = oracle.getPrice(feed, MAX_STALENESS);
        assertEq(price, 100e8, "healthy sequencer should price");
    }

    function test_Sequencer_Down_Reverts() public {
        _enableSequencerCheck();
        uptime.setStatus(1, block.timestamp - GRACE - 1);
        vmExpectRevert(ProtectionOracle.SequencerDown.selector);
        oracle.getPrice(feed, MAX_STALENESS);
    }

    /// @dev The check must fail closed on any answer that is not a clean "up", so a
    ///      malformed feed cannot be mistaken for a healthy sequencer.
    function test_Sequencer_MalformedAnswer_FailsClosed() public {
        _enableSequencerCheck();
        uptime.setStatus(2, block.timestamp - GRACE - 1);
        vmExpectRevert(ProtectionOracle.SequencerDown.selector);
        oracle.getPrice(feed, MAX_STALENESS);
    }

    function test_Sequencer_JustRestarted_RevertsWithinGrace() public {
        _enableSequencerCheck();
        uptime.setStatus(0, block.timestamp - GRACE); // exactly on the boundary
        vmExpectRevert(ProtectionOracle.SequencerGracePeriodNotOver.selector);
        oracle.getPrice(feed, MAX_STALENESS);
    }

    function test_Sequencer_RestartGraceExpires_PricesFlowAgain() public {
        _enableSequencerCheck();
        uptime.setStatus(0, block.timestamp - GRACE - 1);

        vmWarp(block.timestamp + 2);
        (uint256 price,) = oracle.getPrice(feed, MAX_STALENESS);
        assertEq(price, 100e8, "prices should be trusted again after the grace window");
    }

    function test_Sequencer_MissingRestartStamp_Reverts() public {
        _enableSequencerCheck();
        uptime.setStatus(0, 0);
        vmExpectRevert(ProtectionOracle.InvalidSequencerFeed.selector);
        oracle.getPrice(feed, MAX_STALENESS);
    }

    function test_Sequencer_FutureRestartStamp_Reverts() public {
        _enableSequencerCheck();
        uptime.setStatus(0, block.timestamp + 1);
        vmExpectRevert(ProtectionOracle.InvalidSequencerFeed.selector);
        oracle.getPrice(feed, MAX_STALENESS);
    }

    function test_Sequencer_CheckCanBeTurnedOffAgain() public {
        _enableSequencerCheck();
        uptime.setStatus(1, block.timestamp - GRACE - 1);
        vmExpectRevert(ProtectionOracle.SequencerDown.selector);
        oracle.getPrice(feed, MAX_STALENESS);

        // Pointing at address(0) disables the check, e.g. migrating to a chain without one
        oracle.setSequencerUptimeFeed(IAggregatorV3(address(0)));
        (uint256 price,) = oracle.getPrice(feed, MAX_STALENESS);
        assertEq(price, 100e8, "disabling the check should restore pricing");
    }

    function test_SetSequencerUptimeFeed_EmitsAndRevertsWhenNotOwner() public {
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(Ownable.Unauthorized.selector);
        oracle.setSequencerUptimeFeed(uptime);
    }

    function test_SetSequencerGracePeriod_OwnerOnlyAndCapped() public {
        uint256 cap = oracle.MAX_SEQUENCER_GRACE_PERIOD();

        oracle.setSequencerGracePeriod(30 minutes);
        assertEq(oracle.sequencerGracePeriod(), 30 minutes, "grace period should update");

        vmExpectRevert(ProtectionOracle.GracePeriodTooLong.selector);
        oracle.setSequencerGracePeriod(cap + 1);

        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(Ownable.Unauthorized.selector);
        oracle.setSequencerGracePeriod(0);
    }

    function test_Constructor_RevertsOnGracePeriodAboveCap() public {
        uint256 cap = oracle.MAX_SEQUENCER_GRACE_PERIOD();

        bool reverted;
        try new ProtectionOracle(uptime, cap + 1) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "constructor must reject a grace period above the cap");
    }

    function bound(uint256 value, uint256 low, uint256 high) internal pure returns (uint256) {
        if (value < low) return low;
        if (value > high) return high;
        return value;
    }
}
