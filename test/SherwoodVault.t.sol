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
    address internal depositor2 = vmMakeAddr("second depositor");
    address internal buyer = vmMakeAddr("note buyer");
    address internal recipient = vmMakeAddr("payout recipient");

    uint256 constant BUFFER_20 = 2000;
    uint256 constant FEE_10_PERCENT = 1000;

    function setUp() public {
        usdg = new MockERC20("Global Dollar", "USDG", 18);
        vault = new SherwoodVault(usdg, BUFFER_20, FEE_10_PERCENT, address(this));
        vault.setNoteContract(note);
        vmLabel(note, "note contract");
        vmLabel(depositor, "depositor");
        vmLabel(depositor2, "second depositor");
        vmLabel(buyer, "note buyer");
        vmLabel(recipient, "payout recipient");
    }

    function _depositInto(SherwoodVault v, address who, uint256 amount) internal {
        usdg.mint(who, amount);
        vmStartPrank(who);
        usdg.approve(address(v), amount);
        v.deposit(amount);
        vmStopPrank();
    }

    function _deposit(uint256 amount) internal {
        _depositInto(vault, depositor, amount);
    }

    function _reserve(uint256 noteId, uint256 premium, uint256 liability) internal {
        usdg.mint(buyer, premium);
        vmStartPrank(buyer);
        usdg.approve(address(vault), premium);
        vmStopPrank();
        vmPrank(note);
        vault.reserveFor(noteId, buyer, premium, liability);
    }

    /// @dev deposits 1011.25, reserved 400, pending fees 1.25, backer shares 1000.
    ///      capacity = 1011.25 * 0.8 - 400 = 409 (the fee slice never backs notes).
    function _fundedAndReserved(uint256 depositAmt, uint256 premium, uint256 liability) internal {
        _deposit(depositAmt);
        _reserve(1, premium, liability);
    }

    // ------------------------------------------------------------------
    // deposit
    // ------------------------------------------------------------------

    function test_Deposit_MovesTokensAndCounts() public {
        _deposit(1000e18);

        assertEq(vault.totalDeposits(), 1000e18, "deposits not counted");
        assertEq(vault.sharesOf(depositor), 1000e18, "shares not minted 1:1 into empty vault");
        assertEq(vault.totalShares(), 1000e18, "share supply not tracked");
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
    }

    function test_AvailableCapacity_ClampsAtZero() public {
        SherwoodVault v = new SherwoodVault(usdg, 5000, FEE_10_PERCENT, address(this));
        v.setNoteContract(note);
        _depositInto(v, depositor, 1000e18);

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
        // 90% of the premium joins the backing pool; 10% parks in the fee bucket
        assertEq(vault.totalDeposits(), 1011.25e18, "backer premium should join deposits");
        assertEq(vault.pendingProtocolFees(), 1.25e18, "protocol share should accrue");
        assertEq(vault.reserved(), 400e18, "liability not reserved");
        assertEq(usdg.balanceOf(address(vault)), 1012.5e18, "premium tokens must arrive");
        assertEq(usdg.balanceOf(address(vault)), vault.totalDeposits() + vault.pendingProtocolFees(), "balance must equal deposits plus fees");
    }

    function test_ReserveFor_SplitsPremiumBetweenBackersAndProtocol() public {
        _deposit(1000e18);
        _reserve(1, 100e18, 0);

        assertEq(vault.totalDeposits(), 1090e18, "backer share joins deposits");
        assertEq(vault.pendingProtocolFees(), 10e18, "protocol share accrues outside deposits");
        // The fee slice never backs notes: capacity is computed on deposits only
        assertEq(vault.availableCapacity(), 1090e18 * 8000 / 10_000, "capacity must exclude the fee bucket");
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
        assertEq(vault.pendingProtocolFees(), 0, "no fee accrued");
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
        assertEq(vault.pendingProtocolFees(), 0, "zero premium accrues no fee");
    }

    // ------------------------------------------------------------------
    // settlePayout
    // ------------------------------------------------------------------

    function test_SettlePayout_TransfersAndReleases() public {
        _fundedAndReserved(1000e18, 12.5e18, 400e18);

        vmPrank(note);
        vault.settlePayout(1, recipient, 400e18, 100e18);

        assertEq(usdg.balanceOf(recipient), 100e18, "payout not delivered");
        assertEq(vault.reserved(), 0, "liability should release");
        assertEq(vault.totalDeposits(), 911.25e18, "payout should leave deposits");
        assertEq(usdg.balanceOf(address(vault)), 912.5e18, "balance tracks deposits plus fees");
    }

    function test_SettlePayout_ZeroPayout_ReleasesWithoutTransfer() public {
        _fundedAndReserved(1000e18, 12.5e18, 400e18);

        uint256 recipientBefore = usdg.balanceOf(recipient);
        vmPrank(note);
        vault.settlePayout(1, recipient, 400e18, 0);

        assertEq(usdg.balanceOf(recipient), recipientBefore, "nothing should transfer");
        assertEq(vault.reserved(), 0, "liability should release");
        assertEq(vault.totalDeposits(), 1011.25e18, "deposits unchanged on zero payout");
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
        // vault now holds 399.5, less than the 400 payout; deposits say 1011.25

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
    // backer withdrawals: only funds above reserved collateral AND the buffer
    // ------------------------------------------------------------------

    function test_Withdraw_PreservesReservedCollateralAndBuffer() public {
        _fundedAndReserved(1000e18, 12.5e18, 400e18);

        // deposits 1011.25, reserved 400, buffer 20% -> usable 809, so 409 is takeable
        assertEq(vault.availableCapacity(), 409e18, "free capacity after the split");

        // One wei past the line is either reserved collateral or the reserve buffer
        vmStartPrank(depositor);
        vmExpectRevert(SherwoodVault.EncumberedFunds.selector);
        vault.withdraw(409e18 + 1);

        vault.withdraw(409e18);
        vmStopPrank();
        assertEq(usdg.balanceOf(depositor), 409e18, "withdrawal should move free funds");
        assertEq(vault.reserved(), 400e18, "reserved collateral must not move");
        assertLe(vault.reserved(), vault.totalDeposits() - (vault.totalDeposits() * 2000) / 10_000, "inv1 must survive the withdrawal");

        // Repeated cap withdrawals converge on reserved == usable and never breach it:
        // the buffer is what capacity charges for, so it cannot be withdrawn away.
        vmStartPrank(depositor);
        for (uint256 i = 0; i < 8; i++) {
            uint256 takeable = vault.availableCapacity();
            if (takeable == 0) break;
            vault.withdraw(takeable);
            assertLe(
                vault.reserved(),
                vault.totalDeposits() - (vault.totalDeposits() * 2000) / 10_000,
                "inv1 must hold through repeated withdrawals"
            );
        }
        vmStopPrank();
        assertGe(vault.totalDeposits(), 500e18, "buffer must survive: the deposits floor is reserved / (1 - buffer)");
        assertEq(usdg.balanceOf(address(vault)), vault.totalDeposits() + vault.pendingProtocolFees(), "custody must still track accounting");
    }

    function test_Withdraw_WindDownNeedsAnExplicitBufferClear() public {
        _fundedAndReserved(1000e18, 12.5e18, 400e18);

        // With a buffer configured, the buffer is locked by design, not by accident
        vmStartPrank(depositor);
        vmExpectRevert(SherwoodVault.EncumberedFunds.selector);
        vault.withdraw(611.25e18);
        vmStopPrank();

        // Clearing the buffer is the explicit wind-down step that unlocks the rest
        vault.setBufferBps(0);
        assertEq(vault.availableCapacity(), 611.25e18, "reserved-only cap once the buffer clears");

        vmStartPrank(depositor);
        vault.withdraw(611.25e18);
        vmStopPrank();
        assertEq(vault.totalDeposits(), 400e18, "only reserved collateral should remain");
        assertEq(vault.reserved(), 400e18, "reserved collateral must stay fully backed");
        assertEq(usdg.balanceOf(address(vault)), 401.25e18, "custody covers the reserve plus the fee bucket");
    }

    function test_Withdraw_RevertsAboveOwnShares() public {
        _deposit(1000e18); // 1000 shares
        _depositInto(vault, depositor2, 100e18); // 100 shares; shared capacity 880

        // 110 is well inside capacity but costs 110 shares — depositor2 holds 100
        vmStartPrank(depositor2);
        vmExpectRevert(SherwoodVault.InsufficientShares.selector);
        vault.withdraw(110e18);
        vmStopPrank();

        // A non-holder has no claim at all: shares are the permission, not ownership
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(SherwoodVault.InsufficientShares.selector);
        vault.withdraw(1);
    }

    function test_Redeem_PaysProRataShareOfDepositsAndPremiums() public {
        _deposit(1000e18); // 1000 shares
        _reserve(1, 100e18, 0); // +90 backer premiums -> deposits 1090, shares 1000

        // A later depositor buys in at the appreciated rate: 109 for 100 shares
        _depositInto(vault, depositor2, 109e18);
        assertEq(vault.sharesOf(depositor2), 100e18, "later depositor should get pro-rata shares");
        assertEq(vault.totalDeposits(), 1199e18, "deposits after second entry");
        assertEq(vault.totalShares(), 1100e18, "shares after second entry");

        // The first backer redeems everything and takes exactly their claim:
        // 1000/1100 of 1199 = 1090 = their deposit plus 100% of the backer premium.
        // The 20% buffer would lock most of that in, so this is an explicit wind-down.
        vault.setBufferBps(0);
        vmStartPrank(depositor);
        vault.redeem(1000e18);
        vmStopPrank();
        assertEq(usdg.balanceOf(depositor), 1090e18, "first backer earns the premiums pro rata");
        assertEq(vault.totalDeposits(), 109e18, "remaining deposits belong to the second backer");
        assertEq(vault.sharesOf(depositor), 0, "shares burned");
    }

    // ------------------------------------------------------------------
    // protocol fees
    // ------------------------------------------------------------------

    function test_ClaimProtocolFees_PaysTreasuryWithoutTouchingBacking() public {
        _fundedAndReserved(1000e18, 12.5e18, 400e18);

        uint256 capacityBefore = vault.availableCapacity();
        uint256 depositsBefore = vault.totalDeposits();

        vault.claimProtocolFees();

        assertEq(usdg.balanceOf(address(this)), 1.25e18, "treasury should receive the fee bucket");
        assertEq(vault.pendingProtocolFees(), 0, "bucket should drain");
        assertEq(vault.totalDeposits(), depositsBefore, "backing untouched by the fee claim");
        assertEq(vault.availableCapacity(), capacityBefore, "capacity untouched by the fee claim");
        assertEq(vault.reserved(), 400e18, "reserved collateral untouched");
        assertEq(usdg.balanceOf(address(vault)), vault.totalDeposits(), "balance folds back to deposits");
    }

    function test_ClaimProtocolFees_RevertsOnEmptyBucket() public {
        vmExpectRevert(SherwoodVault.InvalidAmount.selector);
        vault.claimProtocolFees();
    }

    function test_ClaimProtocolFees_RevertsWhenNotOwner() public {
        _deposit(1000e18);
        _reserve(1, 100e18, 0); // accrues 10 to the fee bucket
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(Ownable.Unauthorized.selector);
        vault.claimProtocolFees();
    }

    function test_SetFeeTerms_RoundTripCapAndZeroTreasury() public {
        vault.setFeeTerms(2500, vmMakeAddr("new treasury"));
        assertEq(vault.protocolFeeBps(), 2500, "fee up to the hard cap should land");
        assertEq(vault.treasury(), vmMakeAddr("new treasury"), "treasury should update");

        vmExpectRevert(SherwoodVault.FeeTooHigh.selector);
        vault.setFeeTerms(2501, vmMakeAddr("new treasury"));
        vmExpectRevert(SherwoodVault.ZeroTreasury.selector);
        vault.setFeeTerms(1000, address(0));
    }

    function test_SetFeeTerms_RevertsWhenNotOwner() public {
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(Ownable.Unauthorized.selector);
        vault.setFeeTerms(100, vmMakeAddr("t"));
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

    /// @dev Raising the buffer lowers the usable line, so reserves taken under a smaller
    ///      buffer can end up sitting above it. That is invariant 1 broken by an admin
    ///      call rather than by any user, so the raise is refused outright.
    function test_SetBufferBps_RejectsARaiseThatWouldStrandReserves() public {
        SherwoodVault open = new SherwoodVault(usdg, 0, FEE_10_PERCENT, address(this)); // a vault allowed to sell to full coverage
        open.setNoteContract(note);
        _depositInto(open, depositor, 1000e18);

        vmPrank(note);
        open.reserveFor(1, buyer, 0, 1000e18); // buffer 0 -> the whole book may be sold
        assertEq(open.availableCapacity(), 0, "fully committed");
        assertEq(open.reserved(), 1000e18, "entire deposit reserved");

        // 20% of 1000 leaves 800 usable against 1000 reserved: invariant 1 would break
        vmExpectRevert(SherwoodVault.BufferBreachesReserves.selector);
        open.setBufferBps(2000);
        assertEq(open.bufferBps(), 0, "the rejected raise must not move the buffer");

        // Once the reserve is released the same raise is accepted
        vmPrank(note);
        open.settlePayout(1, recipient, 1000e18, 0);
        open.setBufferBps(2000);
        assertEq(open.bufferBps(), 2000, "raise should land once reserves are clear");
    }

    function test_SetBufferBps_AcceptsRaisesWithHeadroomAndEveryLowering() public {
        _fundedAndReserved(1000e18, 12.5e18, 400e18); // deposits 1011.25, reserved 400, buffer 20%

        // 20% -> 50% still leaves 505.625 usable against 400 reserved, so it is allowed
        vault.setBufferBps(5000);
        assertEq(vault.bufferBps(), 5000, "a raise with headroom should land");
        assertEq(vault.availableCapacity(), 105.625e18, "capacity shrinks with the usable line");

        // Lowering only ever raises the usable line, so it can never strand reserves
        vault.setBufferBps(0);
        assertEq(vault.bufferBps(), 0, "a lowering should land");
        assertEq(vault.availableCapacity(), 611.25e18, "capacity grows with the usable line");
    }

    function test_SetBufferBps_RevertsWhenNotOwner() public {
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(Ownable.Unauthorized.selector);
        vault.setBufferBps(3000);
    }

    function test_SetNoteContract_IsSetOnce() public {
        // The fixture wired this vault at setUp; a second binding — even to a
        // legitimate address — is refused, because repointing mid-life would strand
        // the active notes' reserves behind the old contract's onlyNote gate.
        address newNote = vmMakeAddr("note v2");
        vmExpectRevert(SherwoodVault.AlreadySet.selector);
        vault.setNoteContract(newNote);

        vmExpectRevert(SherwoodVault.AlreadySet.selector);
        vault.setNoteContract(address(0));
        assertEq(vault.noteContract(), address(note), "binding unchanged");

        // A fresh vault takes exactly one binding and then locks.
        SherwoodVault fresh = new SherwoodVault(usdg, 2000, FEE_10_PERCENT, address(this));
        vmExpectRevert(SherwoodVault.InvalidAmount.selector);
        fresh.setNoteContract(address(0));
        fresh.setNoteContract(vmMakeAddr("first note"));
        assertEq(fresh.noteContract(), vmMakeAddr("first note"), "first binding lands");
        vmExpectRevert(SherwoodVault.AlreadySet.selector);
        fresh.setNoteContract(vmMakeAddr("second note"));
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
        SherwoodVault v = new SherwoodVault(usdg, 2000, FEE_10_PERCENT, address(this));
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
            } else if (action == 3 && deposits > 0) {
                // a depositor withdrawal beat: inv1 and the capacity gate together
                uint256 takeable = v.availableCapacity();
                if (takeable > 0) {
                    vmStartPrank(depositor);
                    v.withdraw(takeable > deposits ? deposits : takeable);
                    vmStopPrank();
                    deposits = v.totalDeposits();
                }
            }

            // Invariant 1: reserved fits inside deposits minus buffer
            assertGe(
                deposits - (deposits * 2000) / 10_000,
                v.reserved(),
                "inv1 broken: reserved exceeds usable deposits"
            );
            // Invariant 4: real token balance covers reserved AND the fee bucket
            assertGe(usdg.balanceOf(address(v)), v.reserved() + v.pendingProtocolFees(), "inv4 broken: vault underfunded");
        }
    }

    function bound(uint256 value, uint256 low, uint256 high) internal pure returns (uint256) {
        if (value < low) return low;
        if (value > high) return high;
        return value;
    }
}
