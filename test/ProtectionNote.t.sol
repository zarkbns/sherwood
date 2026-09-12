// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {ProtectionNote} from "../src/ProtectionNote.sol";
import {ProtectionMath} from "../src/ProtectionMath.sol";
import {ProtectionOracle} from "../src/ProtectionOracle.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {SherwoodVault} from "../src/SherwoodVault.sol";
import {MockERC20, MockAggregator} from "./Mocks.sol";

/// @dev Shared fixture: registry + oracle + vault + note wired together, TSLA
///      registered against a mock feed stamped at T0, vault funded, buyer funded.
abstract contract NoteFixture is TestBase {
    MockERC20 internal settlement;
    SherwoodVault internal vault;
    AssetRegistry internal registry;
    ProtectionOracle internal oracle;
    MockAggregator internal feed;
    ProtectionNote internal note;

    address internal tsla = vmMakeAddr("TSLA token");
    address internal depositor = vmMakeAddr("depositor");
    address internal buyer = vmMakeAddr("buyer");
    address internal trader = vmMakeAddr("trader");

    uint256 constant T0 = 1_700_000_000;
    uint256 constant AMOUNT_5 = 5e18;
    uint256 constant ENTRY_100 = 100e8;
    uint256 constant LEVEL_70 = 70e16;
    uint256 constant LEVEL_80 = 80e16;
    uint256 constant LEVEL_90 = 90e16;
    uint256 constant DUR_7D = 7 days;
    uint256 constant DUR_1D = 1 days;
    uint256 constant DUR_14D = 14 days;
    uint256 constant DUR_30D = 30 days;

    function _deploy(uint8 settlementDecimals) internal {
        vmWarp(T0);
        settlement = new MockERC20("settlement", "STBL", settlementDecimals);
        registry = new AssetRegistry();
        oracle = new ProtectionOracle();
        vault = new SherwoodVault(settlement, 2000);
        note = new ProtectionNote(registry, oracle, vault);
        vault.setNoteContract(address(note));

        feed = new MockAggregator(8);
        feed.setPrice(100e8);
        registry.registerAsset(tsla, "TSLA", feed, 72 hours);
    }

    function _fundVault(uint256 amount) internal {
        settlement.mint(depositor, amount);
        vmStartPrank(depositor);
        settlement.approve(address(vault), amount);
        vault.deposit(amount);
        vmStopPrank();
    }

    function _fundBuyer(uint256 amount) internal {
        settlement.mint(buyer, amount);
        vmStartPrank(buyer);
        settlement.approve(address(vault), amount);
        vmStopPrank();
    }

    function _buy(address who, uint256 amount, uint256 level, uint256 duration) internal returns (uint256) {
        vmPrank(who);
        return note.create(tsla, amount, level, duration);
    }

    function bound(uint256 value, uint256 low, uint256 high) internal pure returns (uint256) {
        if (value < low) return low;
        if (value > high) return high;
        return value;
    }
}

contract ProtectionNoteTest is NoteFixture {
    // Mirrors of ProtectionNote events for expectEmit assertions
    event NoteCreated(
        uint256 indexed noteId,
        address indexed owner,
        address indexed asset,
        uint256 amount,
        uint256 entryPrice,
        uint256 level,
        uint256 expiry,
        uint256 premiumUSD18,
        uint256 protectedUSD18,
        uint256 liabilityToken
    );
    event NoteSettled(uint256 indexed noteId, uint256 settlementPrice, uint256 payoutToken, address indexed recipient);

    function setUp() public {
        _deploy(18);
        _fundVault(1000e18);
        _fundBuyer(1e24);
    }

    // ------------------------------------------------------------------
    // create
    // ------------------------------------------------------------------

    function test_Create_StoresNoteWithSpecTerms() public {
        uint256 id = _buy(buyer, AMOUNT_5, LEVEL_80, DUR_7D);

        assertEq(id, 1, "first note id");
        assertEq(note.nextId(), 1, "counter should advance");

        (
            address owner,
            address asset,
            uint256 amount,
            uint256 entryPrice,
            uint256 level,
            uint256 expiry,
            uint256 premiumUSD18,
            uint256 protectedUSD18,
            uint256 liabilityToken,
            ProtectionNote.Status status
        ) = note.notes(id);

        assertEq(owner, buyer, "buyer should own the note");
        assertEq(asset, tsla, "asset mismatch");
        assertEq(amount, AMOUNT_5, "amount mismatch");
        assertEq(entryPrice, ENTRY_100, "entry price mismatch");
        assertEq(level, LEVEL_80, "level mismatch");
        assertEq(expiry, T0 + DUR_7D, "expiry mismatch");
        assertEq(premiumUSD18, 12.5e18, "premium mismatch");
        assertEq(protectedUSD18, 400e18, "protected value mismatch");
        assertEq(liabilityToken, 400e18, "liability mismatch");
        assertEq(uint8(status), uint8(ProtectionNote.Status.ACTIVE), "status mismatch");
    }

    function test_Create_SupportsOneDayDuration() public {
        uint256 id = _buy(buyer, AMOUNT_5, LEVEL_80, DUR_1D);

        (, , , , , uint256 expiry, uint256 premiumUSD18, , , ) = note.notes(id);
        assertEq(expiry, T0 + DUR_1D, "1-day expiry mismatch");
        // 500e18 position value at 225 bps (base 100 + tier 100 + duration 25)
        assertEq(premiumUSD18, 11.25e18, "1-day premium mismatch");
    }

    function test_Create_CollectsPremiumAndReservesLiability() public {
        _buy(buyer, AMOUNT_5, LEVEL_80, DUR_7D);

        assertEq(settlement.balanceOf(buyer), 1e24 - 12.5e18, "premium not collected");
        assertEq(vault.totalDeposits(), 1012.5e18, "premium should join deposits");
        assertEq(vault.reserved(), 400e18, "liability not reserved");
        assertEq(settlement.balanceOf(address(vault)), 1012.5e18, "vault must hold the tokens");
    }

    function test_Create_IncrementingIds() public {
        uint256 first = _buy(buyer, AMOUNT_5, LEVEL_80, DUR_7D);
        uint256 second = _buy(buyer, AMOUNT_5, LEVEL_70, DUR_14D);
        assertEq(first, 1, "first id");
        assertEq(second, 2, "second id");
        assertEq(note.nextId(), 2, "counter should advance per note");
    }

    function test_Create_EmitsNoteCreated() public {
        vmExpectEmit(true, true, true, true);
        emit NoteCreated(1, buyer, tsla, AMOUNT_5, ENTRY_100, LEVEL_80, T0 + DUR_7D, 12.5e18, 400e18, 400e18);
        _buy(buyer, AMOUNT_5, LEVEL_80, DUR_7D);
    }

    function test_Create_RevertsOnUnregisteredAsset() public {
        vmPrank(buyer);
        vmExpectRevert(ProtectionNote.UnsupportedAsset.selector);
        note.create(vmMakeAddr("unknown token"), AMOUNT_5, LEVEL_80, DUR_7D);
    }

    function test_Create_RevertsOnInactiveAsset() public {
        registry.setAssetActive(tsla, false);
        vmPrank(buyer);
        vmExpectRevert(ProtectionNote.AssetInactive.selector);
        note.create(tsla, AMOUNT_5, LEVEL_80, DUR_7D);
    }

    function test_Create_RevertsOnZeroAmount() public {
        vmPrank(buyer);
        vmExpectRevert(ProtectionNote.InvalidAmount.selector);
        note.create(tsla, 0, LEVEL_80, DUR_7D);
    }

    function test_Create_RevertsOnUnsupportedLevel() public {
        vmPrank(buyer);
        vmExpectRevert(ProtectionMath.InvalidLevel.selector);
        note.create(tsla, AMOUNT_5, 75e16, DUR_7D);
    }

    function test_Create_RevertsOnUnsupportedDuration() public {
        vmPrank(buyer);
        vmExpectRevert(ProtectionMath.InvalidDuration.selector);
        note.create(tsla, AMOUNT_5, LEVEL_80, 10 days);
    }

    function test_Create_RevertsOnStaleEntryPrice_NothingCollected() public {
        vmWarp(T0 + 73 hours); // feed stamped at T0, staleness 72h
        vmExpectRevert(ProtectionOracle.StalePrice.selector);
        _buy(buyer, AMOUNT_5, LEVEL_80, DUR_7D);

        // Invariant 5 through the note: nothing moved
        assertEq(settlement.balanceOf(buyer), 1e24, "buyer untouched");
        assertEq(vault.reserved(), 0, "nothing reserved");
        assertEq(note.nextId(), 0, "no note counted");
    }

    function test_Create_RevertsWhenCapacityExceeded_NothingCollected() public {
        // 10 TSLA @ $100, 80%, 7d: premium 25 + liability 800 = 825 > 800 capacity
        vmPrank(buyer);
        vmExpectRevert(SherwoodVault.InsufficientCapacity.selector);
        note.create(tsla, 10e18, LEVEL_80, DUR_7D);

        assertEq(settlement.balanceOf(buyer), 1e24, "buyer untouched");
        assertEq(vault.reserved(), 0, "nothing reserved");
        assertEq(note.nextId(), 0, "no note counted");
    }

    // ------------------------------------------------------------------
    // settle
    // ------------------------------------------------------------------

    function _buySpecAndExpire() internal returns (uint256 id) {
        id = _buy(buyer, AMOUNT_5, LEVEL_80, DUR_7D);
        vmWarp(T0 + DUR_7D + 1);
    }

    function test_Settle_PayoutsFloorDifference() public {
        uint256 id = _buySpecAndExpire();
        feed.setPrice(60e8);

        uint256 buyerBefore = settlement.balanceOf(buyer);
        note.settle(id);

        assertEq(settlement.balanceOf(buyer), buyerBefore + 100e18, "payout should be $100");
        assertEq(vault.reserved(), 0, "liability released");
        assertEq(vault.totalDeposits(), 912.5e18, "payout leaves deposits");
        assertEq(settlement.balanceOf(address(vault)), 912.5e18, "vault balance tracks deposits");

        (, , , , , , , , , ProtectionNote.Status status) = note.notes(id);
        assertEq(uint8(status), uint8(ProtectionNote.Status.SETTLED), "note should be SETTLED");
    }

    function test_Settle_NoPayoutAboveFloor_KeepsUpside() public {
        uint256 id = _buySpecAndExpire();
        feed.setPrice(120e8);

        uint256 buyerBefore = settlement.balanceOf(buyer);
        note.settle(id);

        assertEq(settlement.balanceOf(buyer), buyerBefore, "no payout above floor");
        assertEq(vault.reserved(), 0, "liability still released");
        assertEq(vault.totalDeposits(), 1012.5e18, "deposits unchanged");
    }

    function test_Settle_ZeroAtExactFloor() public {
        uint256 id = _buySpecAndExpire();
        feed.setPrice(80e8);

        uint256 buyerBefore = settlement.balanceOf(buyer);
        note.settle(id);
        assertEq(settlement.balanceOf(buyer), buyerBefore, "floor boundary pays nothing");
    }

    function test_Settle_PaysTheBuyer() public {
        uint256 id = _buySpecAndExpire();

        feed.setPrice(60e8);
        uint256 buyerBefore = settlement.balanceOf(buyer);
        note.settle(id);

        assertEq(settlement.balanceOf(buyer), buyerBefore + 100e18, "payout goes to the buyer");
    }

    function test_Settle_IsPermissionless() public {
        uint256 id = _buySpecAndExpire();
        feed.setPrice(60e8);

        vmPrank(trader);
        note.settle(id);

        assertEq(vault.reserved(), 0, "anyone can settle; owner still paid");
    }

    function test_Settle_RevertsBeforeExpiry() public {
        uint256 id = _buy(buyer, AMOUNT_5, LEVEL_80, DUR_7D);
        vmWarp(T0 + DUR_7D - 1);

        vmExpectRevert(ProtectionNote.NotExpired.selector);
        note.settle(id);
    }

    function test_Settle_RevertsWhenAlreadySettled() public {
        uint256 id = _buySpecAndExpire();
        feed.setPrice(60e8);
        note.settle(id);

        vmExpectRevert(ProtectionNote.AlreadySettled.selector);
        note.settle(id);
    }

    function test_Settle_RevertsOnStaleSettlementPrice_NoteStaysActive() public {
        uint256 id = _buySpecAndExpire();
        vmWarp(T0 + DUR_7D + 73 hours); // past expiry AND past staleness

        vmExpectRevert(ProtectionOracle.StalePrice.selector);
        note.settle(id);

        // Recovery path: refreshed feed settles normally
        feed.setPrice(60e8);
        note.settle(id);
        assertEq(settlement.balanceOf(buyer), 1e24 - 12.5e18 + 100e18, "settles after refresh");
    }

    function test_Settle_EmitsNoteSettled() public {
        uint256 id = _buySpecAndExpire();
        feed.setPrice(60e8);

        vmExpectEmit(true, false, true, true);
        emit NoteSettled(id, 60e8, 100e18, buyer);
        note.settle(id);
    }

    function test_Settle_RevertsOnUnknownNote() public {
        vmExpectRevert(ProtectionNote.NoteNotFound.selector);
        note.settle(99);
    }

    // ------------------------------------------------------------------
    // views
    // ------------------------------------------------------------------

    function test_CalculatePayout_MatchesFormula() public {
        uint256 id = _buy(buyer, AMOUNT_5, LEVEL_80, DUR_7D);

        assertEq(note.calculatePayout(id, 60e8), 100e18, "below floor");
        assertEq(note.calculatePayout(id, 90e8), 0, "between floor and entry");
        assertEq(note.calculatePayout(id, 120e8), 0, "above entry");
        assertEq(
            note.calculatePayout(id, 60e8),
            ProtectionMath.payout(AMOUNT_5, ENTRY_100, LEVEL_80, 60e8),
            "must equal library formula"
        );
    }

    function test_IsSettlable_Lifecycle() public {
        uint256 id = _buy(buyer, AMOUNT_5, LEVEL_80, DUR_7D);

        assertFalse(note.isSettlable(id), "active note not yet expired");
        vmWarp(T0 + DUR_7D + 1);
        assertTrue(note.isSettlable(id), "expired active note should be settlable");
        assertFalse(note.isSettlable(99), "unknown note never settlable");

        feed.setPrice(60e8);
        note.settle(id);
        assertFalse(note.isSettlable(id), "settled note not settlable");
    }

    function test_Quote_MatchesCreateStorage() public {
        uint256 id = _buy(buyer, AMOUNT_5, LEVEL_80, DUR_7D);

        (uint256 premiumUSD18, uint256 protectedUSD18, uint256 expiry) = note.quote(tsla, AMOUNT_5, LEVEL_80, DUR_7D);
        (, , , , , uint256 storedExpiry, uint256 storedPremium, uint256 storedProtected, , ) = note.notes(id);

        assertEq(premiumUSD18, storedPremium, "quote premium must match create");
        assertEq(protectedUSD18, storedProtected, "quote floor must match create");
        assertEq(expiry, storedExpiry, "quote expiry must match create");
    }

    function test_Quote_RevertsOnInactiveAsset() public {
        registry.setAssetActive(tsla, false);
        vmExpectRevert(ProtectionNote.AssetInactive.selector);
        note.quote(tsla, AMOUNT_5, LEVEL_80, DUR_7D);
    }

    // ------------------------------------------------------------------
    // Fuzzed end-to-end: payout always matches math and never exceeds liability
    // ------------------------------------------------------------------

    function testFuzz_Settle_PayoutMatchesMathAndReleasesLiability(
        uint256 amountSeed,
        uint256 entrySeed,
        uint256 settleSeed,
        uint256 levelSeed
    ) public {
        uint256 amount = (1 + amountSeed % 1_000_000) * 1e18;
        uint256 entry = (1 + entrySeed % 1_000_000) * 1e8;
        // Oracle sanity rejects a zero answer, so settlement prices start at 1
        uint256 settlePrice = 1 + settleSeed % (2 * entry - 1);
        uint256 level = LEVEL_70 + 10e16 * (levelSeed % 3);

        uint256 premiumUSD18 = ProtectionMath.premium(
            ProtectionMath.usdValue(amount, entry), ProtectionMath.premiumRateBps(level, DUR_7D)
        );
        uint256 protectedUSD18 = ProtectionMath.protectedValue(amount, entry, level);
        uint256 premiumToken = ProtectionMath.toTokenUnits(premiumUSD18, 18);
        uint256 liabilityToken = ProtectionMath.toTokenUnits(protectedUSD18, 18);

        // Capacity needs usable >= premium + liability: deposit 1.25x with headroom
        _fundVault(((premiumToken + liabilityToken) * 5) / 4 + 1);
        _fundBuyer(premiumToken);
        feed.setPrice(int256(entry)); // oracle must quote the seeded entry price

        vmStartPrank(buyer);
        uint256 id = note.create(tsla, amount, level, DUR_7D);
        vmStopPrank();

        assertEq(vault.reserved(), liabilityToken, "reserved liability");
        uint256 depositsAfterCreate = vault.totalDeposits();

        vmWarp(T0 + DUR_7D + 1);
        feed.setPrice(int256(settlePrice));

        uint256 expectedUSD18 = ProtectionMath.payout(amount, entry, level, settlePrice);
        uint256 expectedToken = ProtectionMath.toTokenUnits(expectedUSD18, 18);
        assertLe(expectedToken, liabilityToken, "inv3: payout must not exceed liability");

        uint256 buyerBefore = settlement.balanceOf(buyer);
        note.settle(id);

        assertEq(settlement.balanceOf(buyer), buyerBefore + expectedToken, "payout must match formula");
        assertEq(vault.reserved(), 0, "liability released on any settlement");
        assertEq(vault.totalDeposits(), depositsAfterCreate - expectedToken, "deposits drop by payout");
    }
}

contract ProtectionNoteUsdcTest is NoteFixture {
    function setUp() public {
        _deploy(6);
        _fundVault(2000e6);
        _fundBuyer(1000e6);
    }

    function test_SpecExample_In6DecTokenUnits() public {
        vmStartPrank(buyer);
        uint256 id = note.create(tsla, AMOUNT_5, LEVEL_80, DUR_7D);
        vmStopPrank();

        (, , , , , , uint256 premiumUSD18, uint256 protectedUSD18, uint256 liabilityToken,) = note.notes(id);
        // USD-18 math is unchanged by token decimals
        assertEq(premiumUSD18, 12.5e18, "premium usd");
        assertEq(protectedUSD18, 400e18, "protected usd");
        // Token-side conversion: /1e12 for 6 decimals
        assertEq(liabilityToken, 400e6, "liability in USDC units");
        assertEq(settlement.balanceOf(buyer), 1000e6 - 12.5e6, "premium collected in USDC");

        vmWarp(T0 + DUR_7D + 1);
        feed.setPrice(60e8);
        note.settle(id);

        assertEq(settlement.balanceOf(buyer), 1000e6 - 12.5e6 + 100e6, "payout 100 USDC");
        assertEq(vault.reserved(), 0, "liability released");
        assertEq(vault.totalDeposits(), 2000e6 + 12.5e6 - 100e6, "accounting consistent");
    }

    function test_Truncation_NeverOverpaysLiability() public {
        // One wei of stock makes USD-18 values indivisible by 1e12; conversion
        // must truncate so payout stays within reserved liability.
        vmStartPrank(buyer);
        uint256 id = note.create(tsla, 5e18 + 1, LEVEL_80, DUR_7D);
        vmStopPrank();

        (, , , , , , , , uint256 liabilityToken,) = note.notes(id);
        assertEq(liabilityToken, 400e6, "floor truncates down to whole USDC");

        vmWarp(T0 + DUR_7D + 1);
        feed.setPrice(60e8);
        uint256 buyerBefore = settlement.balanceOf(buyer);
        note.settle(id);

        uint256 paid = settlement.balanceOf(buyer) - buyerBefore;
        assertLe(paid, liabilityToken, "inv3 through truncation");
    }
}
