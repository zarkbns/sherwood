// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {SherwoodVault} from "../src/SherwoodVault.sol";
import {Ownable} from "../src/Ownable.sol";
import {MockERC20} from "./Mocks.sol";

contract SherwoodVaultTest is TestBase {
    MockERC20 internal usdg;
    SherwoodVault internal vault;
    address internal note = vmMakeAddr("note contract");
    address internal depositor = vmMakeAddr("depositor");
    address internal buyer = vmMakeAddr("note buyer");
    address internal recipient = vmMakeAddr("payout recipient");

    uint256 constant BUFFER_20 = 2000;

    function setUp() public {
        usdg = new MockERC20("Global Dollar", "USDG", 18);
        vault = new SherwoodVault(usdg, BUFFER_20);
        vault.setNoteContract(note);
        vmLabel(note, "note contract");
        vmLabel(depositor, "depositor");
        vmLabel(buyer, "note buyer");
        vmLabel(recipient, "payout recipient");
    }

    function _deposit(uint256 amount) internal {
        usdg.mint(depositor, amount);
        vmStartPrank(depositor);
        usdg.approve(address(vault), amount);
        vault.deposit(amount);
        vmStopPrank();
    }

    function _reserve(uint256 noteId, uint256 premium, uint256 liability) internal {
        usdg.mint(buyer, premium);
        vmStartPrank(buyer);
        usdg.approve(address(vault), premium);
        vmStopPrank();
        vmPrank(note);
        vault.reserveFor(noteId, buyer, premium, liability);
    }

    // ------------------------------------------------------------------
    // deposit
    // ------------------------------------------------------------------

    function test_Deposit_MovesTokensAndCounts() public {
        _deposit(1000e18);

        assertEq(vault.totalDeposits(), 1000e18, "deposits not counted");
        assertEq(usdg.balanceOf(address(vault)), 1000e18, "tokens not held");
        assertEq(usdg.balanceOf(depositor), 0, "depositor should be drained");
    }

    function test_Deposit_RevertsOnZero() public {
        vmExpectRevert(SherwoodVault.InvalidAmount.selector);
        vault.deposit(0);
    }

    function test_Deposit_RevertsOnFailedTransfer() public {
        // No mint, no approve -> transferFrom returns false -> TransferFailed
        vmPrank(depositor);
        vmExpectRevert(SherwoodVault.TransferFailed.selector);
        vault.deposit(100e18);
    }

    // ------------------------------------------------------------------
    // Capacity math with 20% buffer (invariant 1)
    // ------------------------------------------------------------------

    function test_AvailableCapacity_RespectsBuffer() public {
        _deposit(1000e18);

        // 1000 - 20% = 800 usable
        assertEq(vault.availableCapacity(), 800e18, "capacity should be 800");
        assertEq(vault.freeBalance(), 800e18, "free balance should be 800");
    }

    function test_AvailableCapacity_ClampsAtZero() public {
        SherwoodVault v = new SherwoodVault(usdg, 5000);
        v.setNoteContract(note);
        _deposit(1000e18);
        // need deposits in v, not vault — redo against v
        usdg.mint(depositor, 1000e18);
        vmStartPrank(depositor);
        usdg.approve(address(v), 1000e18);
        v.deposit(1000e18);
        vmStopPrank();

        vmPrank(note);
        v.reserveFor(1, buyer, 0, 500e18);
        assertEq(v.availableCapacity(), 0, "capacity should clamp to 0");

        vmPrank(note);
        vmExpectRevert(SherwoodVault.InsufficientCapacity.selector);
        v.reserveFor(2, buyer, 0, 1);
    }

    // ------------------------------------------------------------------
    // reserveFor: capacity check BEFORE premium collection (invariant 5)
    // ------------------------------------------------------------------

    function test_ReserveFor_CollectsPremiumAndReservesLiability() public {
        _deposit(1000e18);

        // _reserve mints exactly the premium to buyer, so full collection zeroes it
        _reserve(1, 12.5e18, 400e18);

        assertEq(usdg.balanceOf(buyer), 0, "premium not collected");
        assertEq(vault.totalDeposits(), 1012.5e18, "premium should join deposits");
        assertEq(vault.reserved(), 400e18, "liability not reserved");
        assertEq(usdg.balanceOf(address(vault)), 1012.5e18, "premium tokens must arrive");
    }

    function test_ReserveFor_RevertsWhenCapacityExceeded_NothingCollected() public {
        _deposit(1000e18);
        usdg.mint(buyer, 100e18);
        vmStartPrank(buyer);
        usdg.approve(address(vault), 100e18);
        vmStopPrank();

        uint256 buyerBefore = usdg.balanceOf(buyer);
        uint256 vaultBefore = usdg.balanceOf(address(vault));

        // premium + liability = 100 + 750 = 850 > 800 available
        vmPrank(note);
        vmExpectRevert(SherwoodVault.InsufficientCapacity.selector);
        vault.reserveFor(1, buyer, 100e18, 750e18);

        // Invariant 5: capacity checked before premium movement
        assertEq(usdg.balanceOf(buyer), buyerBefore, "buyer should be untouched");
        assertEq(usdg.balanceOf(address(vault)), vaultBefore, "vault should be untouched");
        assertEq(vault.totalDeposits(), 1000e18, "deposits unchanged");
        assertEq(vault.reserved(), 0, "nothing reserved");
    }

    function test_ReserveFor_RevertsWhenNotNoteContract() public {
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(SherwoodVault.NotNoteContract.selector);
        vault.reserveFor(1, buyer, 1e18, 10e18);
    }

    function test_ReserveFor_ZeroPremiumAllowed() public {
        _deposit(1000e18);
        _reserve(1, 0, 400e18);
        assertEq(vault.reserved(), 400e18, "liability should reserve with zero premium");
    }

    // ------------------------------------------------------------------
    // settlePayout
    // ------------------------------------------------------------------

    function _fundedAndReserved(uint256 depositAmt, uint256 premium, uint256 liability) internal {
        _deposit(depositAmt);
        _reserve(1, premium, liability);
    }

    function test_SettlePayout_TransfersAndReleases() public {
        _fundedAndReserved(1000e18, 12.5e18, 400e18);

        vmPrank(note);
        vault.settlePayout(1, recipient, 400e18, 100e18);

        assertEq(usdg.balanceOf(recipient), 100e18, "payout not delivered");
        assertEq(vault.reserved(), 0, "liability should release");
        assertEq(vault.totalDeposits(), 912.5e18, "payout should leave deposits");
        assertEq(usdg.balanceOf(address(vault)), 912.5e18, "vault balance must track deposits");
    }

    function test_SettlePayout_ZeroPayout_ReleasesWithoutTransfer() public {
        _fundedAndReserved(1000e18, 12.5e18, 400e18);

        uint256 recipientBefore = usdg.balanceOf(recipient);
        vmPrank(note);
        vault.settlePayout(1, recipient, 400e18, 0);

        assertEq(usdg.balanceOf(recipient), recipientBefore, "nothing should transfer");
        assertEq(vault.reserved(), 0, "liability should release");
        assertEq(vault.totalDeposits(), 1012.5e18, "deposits unchanged on zero payout");
    }

    function test_SettlePayout_RevertsWhenPayoutExceedsLiability() public {
        _fundedAndReserved(1000e18, 12.5e18, 400e18);

        vmPrank(note);
        vmExpectRevert(SherwoodVault.PayoutExceedsLiability.selector);
        vault.settlePayout(1, recipient, 400e18, 400e18 + 1);
    }

    function test_SettlePayout_RevertsWhenVaultUnderfunded() public {
        _fundedAndReserved(1000e18, 12.5e18, 400e18);

        // Simulate an external drain so the real token balance falls below the
        // payout despite accounting still showing it as covered.
        usdg.drain(address(vault), recipient, 613e18);
        // vault now holds 399.5, less than the 400 payout; deposits say 1012.5

        vmPrank(note);
        vmExpectRevert(SherwoodVault.InsufficientVaultBalance.selector);
        vault.settlePayout(1, recipient, 400e18, 400e18);
    }

    function test_SettlePayout_RevertsWhenNotNoteContract() public {
        _fundedAndReserved(1000e18, 12.5e18, 400e18);

        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(SherwoodVault.NotNoteContract.selector);
        vault.settlePayout(1, recipient, 400e18, 100e18);
    }

    // ------------------------------------------------------------------
    // withdrawSurplus: only unencumbered funds (invariant 2)
    // ------------------------------------------------------------------

    function test_WithdrawSurplus_AllowsUnencumberedOnly() public {
        _fundedAndReserved(1000e18, 12.5e18, 400e18);

        // unencumbered = 1012.5 - 400 = 612.5
        vault.withdrawSurplus(depositor, 612.5e18);
        assertEq(usdg.balanceOf(depositor), 612.5e18, "surplus should move");

        // Next wei is reserved collateral -> must revert
        vmExpectRevert(SherwoodVault.EncumberedFunds.selector);
        vault.withdrawSurplus(depositor, 1);
    }

    function test_WithdrawSurplus_RevertsWhenNotOwner() public {
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(Ownable.Unauthorized.selector);
        vault.withdrawSurplus(depositor, 1);
    }

    // ------------------------------------------------------------------
    // Admin
    // ------------------------------------------------------------------

    function test_SetBufferBps_RoundTripAndCap() public {
        vault.setBufferBps(3000);
        assertEq(vault.bufferBps(), 3000, "buffer should update");

        vmExpectRevert(SherwoodVault.BufferTooHigh.selector);
        vault.setBufferBps(5001);
    }

    function test_SetBufferBps_RevertsWhenNotOwner() public {
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(Ownable.Unauthorized.selector);
        vault.setBufferBps(3000);
    }

    function test_SetNoteContract_RotatesAndValidates() public {
        address newNote = vmMakeAddr("note v2");
        vault.setNoteContract(newNote);
        assertEq(vault.noteContract(), newNote, "note contract should rotate");

        vmExpectRevert(SherwoodVault.InvalidAmount.selector);
        vault.setNoteContract(address(0));
    }

    function test_SetNoteContract_RevertsWhenNotOwner() public {
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(Ownable.Unauthorized.selector);
        vault.setNoteContract(vmMakeAddr("note v2"));
    }

    // ------------------------------------------------------------------
    // Spec §6 invariants 1 & 4 fuzzed over deposit/reserve/settle sequences
    // ------------------------------------------------------------------

    function testFuzz_Invariants_HoldOverSequences(uint256 seed, uint8 ops) public {
        ops = uint8(bound(ops, 5, 25));
        SherwoodVault v = new SherwoodVault(usdg, 2000);
        v.setNoteContract(note);

        uint256 deposits = 0;
        uint256 reservedSum = 0;
        uint256 nextNoteId = 1;

        for (uint8 i = 0; i < ops; i++) {
            uint256 action = (seed >> (i * 2)) & 3; // 0..3
            if (action == 0) {
                // deposit between 1 and 100 tokens
                uint256 amt = 1e18 + (seed % 100e18);
                usdg.mint(depositor, amt);
                vmStartPrank(depositor);
                usdg.approve(address(v), amt);
                v.deposit(amt);
                vmStopPrank();
                deposits += amt;
            } else if (action == 1) {
                // reserve a random liability within capacity
                uint256 cap = v.availableCapacity();
                uint256 liability = cap > 0 ? (seed % cap) : 0;
                if (liability > 0) {
                    vmPrank(note);
                    v.reserveFor(nextNoteId, buyer, 0, liability);
                    reservedSum += liability;
                    nextNoteId++;
                }
            } else if (action == 2 && reservedSum > 0) {
                // settle a liability slice with payout <= slice
                uint256 slice = (seed % reservedSum) + 1;
                if (slice > reservedSum) slice = reservedSum;
                vmPrank(note);
                v.settlePayout(nextNoteId, recipient, slice, slice / 2);
                reservedSum -= slice;
                deposits -= slice / 2;
                nextNoteId++;
            }
            // action == 3: no-op beat

            // Invariant 1: reserved fits inside deposits minus buffer
            assertGe(
                deposits - (deposits * 2000) / 10_000,
                v.reserved(),
                "inv1 broken: reserved exceeds usable deposits"
            );
            // Invariant 4: real token balance covers reserved (zero-premium flows only)
            assertGe(usdg.balanceOf(address(v)), v.reserved(), "inv4 broken: vault underfunded");
        }
    }

    function bound(uint256 value, uint256 low, uint256 high) internal pure returns (uint256) {
        if (value < low) return low;
        if (value > high) return high;
        return value;
    }
}
