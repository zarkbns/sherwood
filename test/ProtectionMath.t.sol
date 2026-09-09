// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {ProtectionMath} from "../src/ProtectionMath.sol";

/// @dev Shows how a real ProtectionNote will consume the library before the note
///      contract exists; the same formula is applied to mock note structs.
contract ProtectionMathConsumer {
    function settlePayout(
        uint256 amount,
        uint256 entryPrice,
        uint256 level,
        uint256 settlementPrice
    ) external pure returns (uint256 payout, uint256 liability, uint256 positionValue) {
        liability = ProtectionMath.protectedValue(amount, entryPrice, level);
        payout = ProtectionMath.payout(amount, entryPrice, level, settlementPrice);
        positionValue = ProtectionMath.usdValue(amount, settlementPrice);
    }

    function premiumQuote(uint256 amount, uint256 entryPrice, uint256 level, uint256 duration)
        external
        pure
        returns (uint256 premium, uint256 rateBps)
    {
        uint256 positionValue = ProtectionMath.usdValue(amount, entryPrice);
        rateBps = ProtectionMath.premiumRateBps(level, duration);
        premium = ProtectionMath.premium(positionValue, rateBps);
    }

    function liabilityInToken(uint256 amount, uint256 entryPrice, uint256 level, uint8 decimals)
        external
        pure
        returns (uint256)
    {
        return ProtectionMath.toTokenUnits(ProtectionMath.protectedValue(amount, entryPrice, level), decimals);
    }

    // Depth wrappers: internal library functions compile into the caller, so a
    // direct call from the test frame reverts at depth 1 where expectRevert
    // cannot observe it. Going through an external call keeps revert tests real.
    function rateFor(uint256 level, uint256 duration) external pure returns (uint256) {
        return ProtectionMath.premiumRateBps(level, duration);
    }

    function tokenUnits(uint256 usd18, uint8 decimals) external pure returns (uint256) {
        return ProtectionMath.toTokenUnits(usd18, decimals);
    }
}

contract ProtectionMathTest is TestBase {
    ProtectionMathConsumer internal consumer;

    // 5 tokens (18 dec) at $100.00 (8 dec price)
    uint256 constant AMOUNT_5 = 5e18;
    uint256 constant PRICE_100 = 100e8;
    uint256 constant LEVEL_80 = 80e16;
    uint256 constant DURATION_7D = 7 days;

    function setUp() public {
        consumer = new ProtectionMathConsumer();
    }

    // ------------------------------------------------------------------
    // usdValue
    // ------------------------------------------------------------------

    function test_UsdValue_Basic() public {
        // 5 tokens at $100 = $500
        assertEq(ProtectionMath.usdValue(AMOUNT_5, PRICE_100), 500e18, "5 x $100 != $500");
    }

    function test_UsdValue_ZeroAmount() public {
        assertEq(ProtectionMath.usdValue(0, PRICE_100), 0, "zero amount should be zero");
    }

    function test_UsdValue_ZeroPrice() public {
        assertEq(ProtectionMath.usdValue(AMOUNT_5, 0), 0, "zero price should be zero");
    }

    function test_UsdValue_FractionalPrice() public {
        // 2 tokens at $33.33 (8-dec price 33.33e8)
        assertEq(ProtectionMath.usdValue(2e18, 33.33e8), 66.66e18, "2 x $33.33 != $66.66");
    }

    // ------------------------------------------------------------------
    // protectedValue (floor)
    // ------------------------------------------------------------------

    function test_ProtectedValue_Level80() public {
        // Spec §2: 5 TSLA @ $100, 80% -> $400
        assertEq(ProtectionMath.protectedValue(AMOUNT_5, PRICE_100, LEVEL_80), 400e18, "floor != $400");
    }

    function test_ProtectedValue_Level70() public {
        assertEq(ProtectionMath.protectedValue(AMOUNT_5, PRICE_100, 70e16), 350e18, "floor != $350");
    }

    function test_ProtectedValue_Level90() public {
        assertEq(ProtectionMath.protectedValue(AMOUNT_5, PRICE_100, 90e16), 450e18, "floor != $450");
    }

    function test_ProtectedValue_FloorAlwaysBelowValue() public {
        assertTrue(
            ProtectionMath.protectedValue(AMOUNT_5, PRICE_100, LEVEL_80)
                < ProtectionMath.usdValue(AMOUNT_5, PRICE_100),
            "floor should be below position value"
        );
    }

    // ------------------------------------------------------------------
    // payout — the settlement-critical function (spec §2 manual cases)
    // ------------------------------------------------------------------

    function test_Payout_PriceBelowFloor_PaysDifference() public {
        // Spec: floor $400, settles $60 -> value $300 -> payout $100
        assertEq(ProtectionMath.payout(AMOUNT_5, PRICE_100, LEVEL_80, 60e8), 100e18, "payout != $100");
    }

    function test_Payout_PriceBetweenFloorAndEntry_NoPayout() public {
        // Spec: floor $400, settles $90 -> value $450 -> payout 0
        assertEq(ProtectionMath.payout(AMOUNT_5, PRICE_100, LEVEL_80, 90e8), 0, "payout should be 0");
    }

    function test_Payout_PriceAboveEntry_NoPayout_KeepsUpside() public {
        // Spec: settles $120 -> payout 0, upside untouched
        assertEq(ProtectionMath.payout(AMOUNT_5, PRICE_100, LEVEL_80, 120e8), 0, "payout should be 0");
    }

    function test_Payout_ExactFloor_ZeroPayout() public {
        // Settles exactly at the floor -> boundary is no-payout
        assertEq(ProtectionMath.payout(AMOUNT_5, PRICE_100, LEVEL_80, 80e8), 0, "boundary should be 0");
    }

    function test_Payout_PriceDropsToZero_MaxPayout() public {
        // Price 0 -> payout = full floor
        assertEq(ProtectionMath.payout(AMOUNT_5, PRICE_100, LEVEL_80, 0), 400e18, "payout != full floor");
    }

    function test_Payout_CappedAtFloor_NeverNegative() public {
        // Price 1 (8-dec) -> current value 5e10, so payout is floor minus dust
        uint256 payout = ProtectionMath.payout(AMOUNT_5, PRICE_100, LEVEL_80, 1);
        assertEq(payout, 400e18 - 5e10, "payout should be floor minus dust");
        assertLe(payout, 400e18, "payout must never exceed floor");
    }

    function test_Payout_ZeroAmount() public {
        assertEq(ProtectionMath.payout(0, PRICE_100, LEVEL_80, 10e8), 0, "zero amount pays nothing");
    }

    function test_Payout_AllLevels() public {
        // 70%: floor $350; settle $50 -> value $250 -> payout $100
        assertEq(ProtectionMath.payout(AMOUNT_5, PRICE_100, 70e16, 50e8), 100e18, "70% payout wrong");
        // 90%: floor $450; settle $50 -> value $250 -> payout $200
        assertEq(ProtectionMath.payout(AMOUNT_5, PRICE_100, 90e16, 50e8), 200e18, "90% payout wrong");
    }

    // ------------------------------------------------------------------
    // premium + rate table (spec §2 rate table)
    // ------------------------------------------------------------------

    function test_Premium_SpecExample() public {
        // Spec: $500 position, 80%, 7d -> 250 bps -> $12.50
        (uint256 premium, uint256 rateBps) = consumer.premiumQuote(AMOUNT_5, PRICE_100, LEVEL_80, DURATION_7D);
        assertEq(rateBps, 250, "rate != 250 bps");
        assertEq(premium, 12.5e18, "premium != $12.50");
    }

    function test_PremiumRate_AllTierDurationCombos() public {
        // base 100 + tier {70:100, 80:100, 90:200} + duration {7:50, 14:75, 30:100}
        assertEq(ProtectionMath.premiumRateBps(70e16, 7 days), 250, "70/7 wrong");
        assertEq(ProtectionMath.premiumRateBps(70e16, 14 days), 275, "70/14 wrong");
        assertEq(ProtectionMath.premiumRateBps(70e16, 30 days), 300, "70/30 wrong");
        assertEq(ProtectionMath.premiumRateBps(80e16, 7 days), 250, "80/7 wrong");
        assertEq(ProtectionMath.premiumRateBps(80e16, 14 days), 275, "80/14 wrong");
        assertEq(ProtectionMath.premiumRateBps(80e16, 30 days), 300, "80/30 wrong");
        assertEq(ProtectionMath.premiumRateBps(90e16, 7 days), 350, "90/7 wrong");
        assertEq(ProtectionMath.premiumRateBps(90e16, 14 days), 375, "90/14 wrong");
        assertEq(ProtectionMath.premiumRateBps(90e16, 30 days), 400, "90/30 wrong");
    }

    function test_PremiumRate_RevertsOnUnsupportedLevel() public {
        vmExpectRevert(ProtectionMath.InvalidLevel.selector);
        consumer.rateFor(75e16, 7 days);
    }

    function test_PremiumRate_RevertsOnUnsupportedDuration() public {
        vmExpectRevert(ProtectionMath.InvalidDuration.selector);
        consumer.rateFor(80e16, 10 days);
    }

    function test_Premium_IsZeroForZeroValue() public {
        assertEq(ProtectionMath.premium(0, 250), 0, "zero position premium should be 0");
    }

    // ------------------------------------------------------------------
    // toTokenUnits — settlement-token boundary (spec §2)
    // ------------------------------------------------------------------

    function test_ToTokenUnits_Usdg18Decimals() public {
        // USDG is 18 dec -> identity
        assertEq(ProtectionMath.toTokenUnits(400e18, 18), 400e18, "18-dec conversion wrong");
    }

    function test_ToTokenUnits_Usdc6Decimals() public {
        // Spec: USDC = 6 dec -> /1e12
        assertEq(ProtectionMath.toTokenUnits(400e18, 6), 400e6, "6-dec conversion wrong");
    }

    function test_ToTokenUnits_TruncatesDust() public {
        // $0.000000000001 (1e-12 USD) to 6-dec token truncates to 0 dust
        assertEq(ProtectionMath.toTokenUnits(1, 6), 0, "sub-1-unit should truncate to 0");
    }

    function test_ToTokenUnits_RevertsAbove18Decimals() public {
        vmExpectRevert(ProtectionMath.InvalidDecimals.selector);
        consumer.tokenUnits(1e18, 19);
    }

    // ------------------------------------------------------------------
    // Spec §6 invariant 3: payout <= liability, fuzzed
    // ------------------------------------------------------------------

    function testFuzz_PayoutNeverExceedsFloor(uint256 amount, uint256 entry, uint256 level, uint256 settle)
        public
    {
        amount = bound(amount, 0, 1_000_000e18);
        entry = bound(entry, 1, 1_000_000e8);
        level = bound(level, 0, 1e18);
        settle = bound(settle, 0, type(uint128).max);

        uint256 liability = ProtectionMath.protectedValue(amount, entry, level);
        uint256 paid = ProtectionMath.payout(amount, entry, level, settle);
        assertLe(paid, liability, "invariant 3 broken: payout > liability");
    }

    function testFuzz_PayoutMonotonicInPrice(uint256 entry, uint256 settleA, uint256 settleB) public {
        entry = bound(entry, 1, 1_000_000e8);
        settleA = bound(settleA, 0, entry);
        settleB = bound(settleB, 0, entry);
        if (settleA <= settleB) {
            assertGe(
                ProtectionMath.payout(AMOUNT_5, entry, LEVEL_80, settleA),
                ProtectionMath.payout(AMOUNT_5, entry, LEVEL_80, settleB),
                "payout not monotonic in settlement price"
            );
        } else {
            assertGe(
                ProtectionMath.payout(AMOUNT_5, entry, LEVEL_80, settleB),
                ProtectionMath.payout(AMOUNT_5, entry, LEVEL_80, settleA),
                "payout not monotonic in settlement price"
            );
        }
    }

    // Library functions are internal; expose for fuzz helpers via the consumer
    function bound(uint256 value, uint256 low, uint256 high) internal pure returns (uint256) {
        if (value < low) return low;
        if (value > high) return high;
        return value;
    }
}
