// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {ProtectionOracle} from "../src/ProtectionOracle.sol";
import {MockAggregator} from "./Mocks.sol";

contract ProtectionOracleTest is TestBase {
    ProtectionOracle internal oracle;
    MockAggregator internal feed;

    uint256 constant MAX_STALENESS = 72 hours;

    function setUp() public {
        oracle = new ProtectionOracle();
        feed = new MockAggregator(8);
        vmWarp(1_700_000_000);
        feed.setPrice(100e8);
    }

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

    function bound(uint256 value, uint256 low, uint256 high) internal pure returns (uint256) {
        if (value < low) return low;
        if (value > high) return high;
        return value;
    }
}
