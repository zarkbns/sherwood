// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {NoteFixture} from "./ProtectionNote.t.sol";
import {ProtectionNote} from "../src/ProtectionNote.sol";
import {ProtectionOracle} from "../src/ProtectionOracle.sol";
import {SherwoodVault} from "../src/SherwoodVault.sol";
import {MockERC20, MockAggregator, MockSequencerFeed} from "./Mocks.sol";

/// @title E2E
/// @notice Whole-system rehearsal of the deployment checklist. Wires registry +
///         oracle + vault + note exactly as script/Deploy.s.sol assembles them, then
///         walks real lifecycles — buy, expire, settle with and without payout — and
///         asserts token balances, vault accounting, and the event trail end to end.
contract E2ETest is NoteFixture {
    uint256 constant ENTRY_250 = 250e8;
    uint256 constant PREMIUM_80 = 31.25e18; // 1250e18 position value at 250 bps (80% tier, 7d)
    uint256 constant FLOOR_80_5 = 1000e18; // 5 TSLA at 80% of 250
    uint256 constant PREMIUM_90_2 = 17.5e18; // 500e18 position value at 350 bps (90% tier, 7d)
    uint256 constant FLOOR_90_2 = 450e18; // 2 TSLA at 90% of 250

    // Mirrors of ProtectionNote / SherwoodVault events for expectEmit assertions
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
    event Deposited(address indexed depositor, uint256 amount);
    event CapacityReleased(uint256 indexed noteId, uint256 liability);
    event PayoutExecuted(uint256 indexed noteId, address indexed to, uint256 amount);

    address internal keeper = vmMakeAddr("keeper");

    function setUp() public {
        _deploy(18);
    }

    function test_E2E_PriceFallsBelowFloor_VaultPaysBuyer() public {
        _fundVault(100_000e18);
        _fundBuyer(1e24);
        feed.setPrice(int256(ENTRY_250));

        (uint256 premium, uint256 floorValue, uint256 expiry) = note.quote(tsla, AMOUNT_5, LEVEL_80, DUR_7D);
        assertEq(premium, PREMIUM_80, "quote premium");
        assertEq(floorValue, FLOOR_80_5, "quote floor value");
        assertEq(expiry, T0 + DUR_7D, "quote expiry");

        vmExpectEmit(true, true, true, true);
        emit NoteCreated(1, buyer, tsla, AMOUNT_5, ENTRY_250, LEVEL_80, T0 + DUR_7D, PREMIUM_80, FLOOR_80_5, FLOOR_80_5);
        vmPrank(buyer);
        uint256 id = note.create(tsla, AMOUNT_5, LEVEL_80, DUR_7D);
        assertEq(id, 1, "first note id");

        (
            address owner,
            address asset,
            uint256 amount,
            uint256 entryPrice,
            uint256 level,
            uint256 noteExpiry,
            uint256 premiumUSD18,
            uint256 protectedUSD18,
            uint256 liabilityToken,
            ProtectionNote.Status status
        ) = note.notes(id);
        assertEq(owner, buyer, "note owner");
        assertEq(asset, tsla, "note asset");
        assertEq(amount, AMOUNT_5, "note amount");
        assertEq(entryPrice, ENTRY_250, "note entry price");
        assertEq(level, LEVEL_80, "note level");
        assertEq(noteExpiry, T0 + DUR_7D, "note expiry");
        assertEq(premiumUSD18, PREMIUM_80, "note premium");
        assertEq(protectedUSD18, FLOOR_80_5, "note floor");
        assertEq(liabilityToken, FLOOR_80_5, "note liability (18-dec USDG)");
        assertEq(uint8(status), uint8(ProtectionNote.Status.ACTIVE), "note active");

        assertEq(settlement.balanceOf(buyer), 1e24 - PREMIUM_80, "premium collected from buyer");
        assertEq(vault.reserved(), FLOOR_80_5, "collateral reserved");
        assertEq(vault.totalDeposits(), 100_000e18 + PREMIUM_80, "deposits plus premium");
        assertEq(settlement.balanceOf(address(vault)), 100_000e18 + PREMIUM_80, "vault solvent after create");

        vmWarp(T0 + DUR_7D - 1);
        vmExpectRevert(ProtectionNote.NotExpired.selector);
        vmPrank(keeper);
        note.settle(id);

        vmWarp(T0 + DUR_7D);
        feed.setPrice(150e8);
        vmExpectEmit(true, false, false, true);
        emit CapacityReleased(id, FLOOR_80_5);
        vmExpectEmit(true, true, false, true);
        emit PayoutExecuted(id, buyer, 250e18);
        vmExpectEmit(true, true, true, true);
        emit NoteSettled(id, 150e8, 250e18, buyer);
        vmPrank(keeper);
        note.settle(id);

        assertEq(settlement.balanceOf(buyer), 1e24 - PREMIUM_80 + 250e18, "payout to buyer");
        assertEq(vault.reserved(), 0, "collateral released");
        assertEq(vault.totalDeposits(), 100_000e18 + PREMIUM_80 - 250e18, "deposits minus payout");
        assertEq(settlement.balanceOf(address(vault)), vault.totalDeposits(), "vault balance tracks deposits");
        assertEq(settlement.balanceOf(keeper), 0, "settle is permissionless, not stealable");
        assertFalse(note.isSettlable(id), "settled note not settlable");

        vmExpectRevert(ProtectionNote.AlreadySettled.selector);
        note.settle(id);
    }

    function test_E2E_SettlesAtFloorExactly_NoPayout_PremiumKept() public {
        _fundVault(100_000e18);
        _fundBuyer(1e24);
        feed.setPrice(int256(ENTRY_250));

        vmPrank(buyer);
        uint256 id = note.create(tsla, AMOUNT_5, LEVEL_80, DUR_7D);

        vmWarp(T0 + DUR_7D);
        // Price fell to exactly the floor: payout formula max(0, floor - current) = 0.
        feed.setPrice(200e8);
        vmExpectEmit(true, true, true, true);
        emit NoteSettled(id, 200e8, 0, buyer);
        vmPrank(keeper);
        note.settle(id);

        assertEq(settlement.balanceOf(buyer), 1e24 - PREMIUM_80, "no payout, premium kept");
        assertEq(vault.reserved(), 0, "collateral released without transfer");
        assertEq(vault.totalDeposits(), 100_000e18 + PREMIUM_80, "premium stays in vault");
        assertEq(settlement.balanceOf(address(vault)), 100_000e18 + PREMIUM_80, "vault balance unchanged");
    }

    function test_E2E_CapacityCheck_PrecedesPremiumCollection() public {
        _fundVault(100e18);
        _fundBuyer(1e24);
        feed.setPrice(int256(ENTRY_250));
        assertEq(vault.availableCapacity(), 80e18, "20% buffer held back");

        vmExpectRevert(SherwoodVault.InsufficientCapacity.selector);
        vmPrank(buyer);
        note.create(tsla, 1e18, LEVEL_80, DUR_7D);
        assertEq(settlement.balanceOf(buyer), 1e24, "nothing collected on failed create");
        assertEq(vault.reserved(), 0, "nothing reserved on failed create");
        assertEq(vault.totalDeposits(), 100e18, "deposits untouched on failed create");

        // 0.38 TSLA: premium 2.375e18 + liability 76e18 = 78.375e18, the largest
        // whole-precision fit under the 80e18 cap.
        vmPrank(buyer);
        uint256 id = note.create(tsla, 0.38e18, LEVEL_80, DUR_7D);
        assertEq(id, 1, "exact fit accepted");
        assertEq(settlement.balanceOf(buyer), 1e24 - 2.375e18, "premium collected on fit");
        assertEq(vault.reserved(), 76e18, "liability reserved on fit");
        assertEq(vault.availableCapacity(), 5.9e18, "capacity reflects premium raising deposits");
    }

    function test_E2E_StaleFeedRejected_AtCreateAndAtSettle() public {
        _fundVault(100_000e18);
        _fundBuyer(1e24);

        feed.setUpdatedAt(T0 - 73 hours);
        vmExpectRevert(ProtectionOracle.StalePrice.selector);
        vmPrank(buyer);
        note.create(tsla, AMOUNT_5, LEVEL_80, DUR_7D);

        feed.setPrice(int256(ENTRY_250));
        vmPrank(buyer);
        uint256 id = note.create(tsla, AMOUNT_5, LEVEL_80, DUR_7D);

        vmWarp(T0 + DUR_7D);
        feed.setUpdatedAt(T0 + DUR_7D - 73 hours);
        vmExpectRevert(ProtectionOracle.StalePrice.selector);
        vmPrank(keeper);
        note.settle(id);
        assertTrue(note.isSettlable(id), "stale settle must not consume the note");
        assertEq(vault.reserved(), FLOOR_80_5, "collateral held while price stale");

        feed.setPrice(100e8);
        vmPrank(keeper);
        note.settle(id);
        assertEq(settlement.balanceOf(buyer), 1e24 - PREMIUM_80 + 500e18, "settles once a fresh price arrives");
        assertEq(vault.reserved(), 0, "collateral released after fresh settle");
    }

    /// @dev Robinhood Chain is an L2. While its sequencer is down a feed's `updatedAt`
    ///      can still look fresh on a round that carries a pre-outage price, so the
    ///      staleness guard alone cannot tell the two apart. The uptime gate must stop
    ///      both legs of the lifecycle and release once the restart grace window ends.
    function test_E2E_SequencerOutage_BlocksCreateAndSettle_ResumesAfterGrace() public {
        _fundVault(100_000e18);
        _fundBuyer(1e24);
        feed.setPrice(int256(ENTRY_250));

        MockSequencerFeed uptime = new MockSequencerFeed();
        uptime.setStatus(0, block.timestamp - 1 hours); // up, restart well behind us
        oracle.setSequencerUptimeFeed(uptime);

        vmPrank(buyer);
        uint256 id = note.create(tsla, AMOUNT_5, LEVEL_80, DUR_7D);
        assertEq(vault.reserved(), FLOOR_80_5, "healthy sequencer: the note is created");

        // Outage: no new notes, and an expired note must not settle on a frozen price
        uptime.setStatus(1, block.timestamp);
        vmExpectRevert(ProtectionOracle.SequencerDown.selector);
        vmPrank(buyer);
        note.create(tsla, AMOUNT_5, LEVEL_80, DUR_7D);

        vmWarp(T0 + DUR_7D);
        vmExpectRevert(ProtectionOracle.SequencerDown.selector);
        vmPrank(keeper);
        note.settle(id);
        assertTrue(note.isSettlable(id), "the note survives the outage unsettled");
        assertEq(vault.reserved(), FLOOR_80_5, "collateral stays reserved through the outage");

        // Back up but still inside the grace window: the backlog may carry pre-outage prices
        uptime.setStatus(0, block.timestamp);
        vmExpectRevert(ProtectionOracle.SequencerGracePeriodNotOver.selector);
        vmPrank(keeper);
        note.settle(id);

        // Past the window the note settles normally against the live price
        feed.setPrice(150e8);
        vmWarp(block.timestamp + 2 hours);
        vmPrank(keeper);
        note.settle(id);
        assertEq(settlement.balanceOf(buyer), 1e24 - PREMIUM_80 + 250e18, "settles once the outage clears");
        assertEq(vault.reserved(), 0, "collateral released after the outage");
    }

    function test_E2E_InactiveAsset_BlocksNewNotes_ExistingNotesStillSettle() public {
        _fundVault(100_000e18);
        _fundBuyer(1e24);
        feed.setPrice(int256(ENTRY_250));

        vmPrank(buyer);
        uint256 id = note.create(tsla, AMOUNT_5, LEVEL_80, DUR_7D);

        registry.setAssetActive(tsla, false);
        vmExpectRevert(ProtectionNote.AssetInactive.selector);
        vmPrank(buyer);
        note.create(tsla, AMOUNT_5, LEVEL_80, DUR_7D);

        vmWarp(T0 + DUR_7D);
        feed.setPrice(150e8);
        vmPrank(keeper);
        note.settle(id);
        assertEq(settlement.balanceOf(buyer), 1e24 - PREMIUM_80 + 250e18, "existing note settles normally");
        assertEq(vault.reserved(), 0, "collateral released after settle");
    }

    function test_E2E_TwoBuyers_ReservedTracksLiability_VaultSolventAndSurplusWithdrawable() public {
        _fundVault(100_000e18);
        _fundBuyer(1e24);
        settlement.mint(trader, 1e24);
        stock.mint(trader, 1000e18); // buyer must hold the position they protect
        vmStartPrank(trader);
        settlement.approve(address(vault), 1e24);
        vmStopPrank();
        feed.setPrice(int256(ENTRY_250));

        vmPrank(buyer);
        uint256 id1 = note.create(tsla, AMOUNT_5, LEVEL_80, DUR_7D);
        vmPrank(trader);
        uint256 id2 = note.create(tsla, 2e18, LEVEL_90, DUR_7D);

        assertEq(vault.reserved(), FLOOR_80_5 + FLOOR_90_2, "reserved is the sum of active liabilities");
        assertEq(vault.availableCapacity(), 78_589e18, "capacity after both notes");
        assertGe(settlement.balanceOf(address(vault)), vault.reserved(), "vault solvent while notes active");

        vmWarp(T0 + DUR_7D);
        feed.setPrice(150e8);
        vmPrank(keeper);
        note.settle(id1);
        note.settle(id2);

        assertEq(settlement.balanceOf(buyer), 1e24 - PREMIUM_80 + 250e18, "buyer payout 250");
        assertEq(settlement.balanceOf(trader), 1e24 - PREMIUM_90_2 + 150e18, "trader payout 150");
        assertEq(vault.reserved(), 0, "all liabilities released");
        assertEq(vault.totalDeposits(), 99_648.75e18, "deposits converge to balance");
        assertEq(settlement.balanceOf(address(vault)), 99_648.75e18, "vault balance after payouts");
        assertFalse(note.isSettlable(id1), "note 1 settled");
        assertFalse(note.isSettlable(id2), "note 2 settled");

        vault.withdrawSurplus(depositor, 1e18);
        assertEq(settlement.balanceOf(depositor), 1e18, "surplus withdrawn");

        vmExpectRevert(SherwoodVault.EncumberedFunds.selector);
        vault.withdrawSurplus(depositor, 99_647.75e18 + 1);
    }
}
