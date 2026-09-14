// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {ProtectionOracle} from "../src/ProtectionOracle.sol";
import {ProtectionNote} from "../src/ProtectionNote.sol";
import {SherwoodVault} from "../src/SherwoodVault.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {HookedToken, MockAggregator, MockERC20, VaultStateProbe} from "./Mocks.sol";

/// @title Reentrancy
/// @notice Pins the checks-effects-interactions ordering across the two boundaries that
///         move settlement tokens: `SherwoodVault.reserveFor` / `settlePayout` and
///         `ProtectionNote.create`. Mainnet settles in USDG, which has no transfer
///         hooks, but the vault reserves collateral against whichever token it was
///         deployed with — so the ordering is enforced rather than assumed, and a
///         hook-bearing token must not be able to re-enter past the capacity check or
///         reuse a note id.
contract ReentrancyTest is TestBase {
    uint256 constant T0 = 1_700_000_000;
    uint256 constant AMOUNT_5 = 5e18;
    uint256 constant ENTRY_100 = 100e8;
    uint256 constant LEVEL_80 = 80e16;
    uint256 constant DUR_7D = 7 days;
    uint256 constant BUFFER_20 = 2000;

    // 5 TSLA at $100 behind an 80% floor = $400 of liability; premium at 250 bps = $12.50.
    // Both expressed in the 6-decimal settlement token's units.
    uint256 constant LIABILITY = 400e6;
    uint256 constant PREMIUM = 12.5e6;

    HookedToken internal token;
    MockERC20 internal stock;
    AssetRegistry internal registry;
    ProtectionOracle internal oracle;
    SherwoodVault internal vault;
    ProtectionNote internal note;
    MockAggregator internal feed;

    address internal depositor = vmMakeAddr("depositor");
    address internal buyer = vmMakeAddr("buyer");

    function setUp() public {
        vmWarp(T0);
        token = new HookedToken(6);
        stock = new MockERC20("Tesla", "TSLA", 18);
        registry = new AssetRegistry();
        oracle = new ProtectionOracle(IAggregatorV3(address(0)), 0);
        vault = new SherwoodVault(token, BUFFER_20);
        note = new ProtectionNote(registry, oracle, vault);
        vault.setNoteContract(address(note));

        feed = new MockAggregator(8);
        feed.setPrice(int256(ENTRY_100));
        registry.registerAsset(address(stock), "TSLA", feed, 72 hours);

        // The buyer holds the position it is protecting, and can pay premiums.
        stock.mint(buyer, 100e18);
        token.mint(buyer, 10_000e6);
        vmStartPrank(buyer);
        token.approve(address(vault), type(uint256).max);
        vmStopPrank();
    }

    function _deposit(uint256 amount) internal {
        token.mint(depositor, amount);
        vmStartPrank(depositor);
        token.approve(address(vault), amount);
        vault.deposit(amount);
        vmStopPrank();
    }

    /// @dev Arms a re-entrant `create()` issued from inside the premium pull, signed by
    ///      the token itself. The token therefore needs the stock position and the
    ///      settlement balance that the position guard and premium collection require.
    function _armReentrantCreate(bool swallow) internal {
        stock.mint(address(token), 100e18);
        token.mint(address(token), 10_000e6);
        vmStartPrank(address(token));
        token.approve(address(vault), type(uint256).max);
        vmStopPrank();

        token.arm(
            address(note),
            abi.encodeWithSignature(
                "create(address,uint256,uint256,uint256)", address(stock), AMOUNT_5, LEVEL_80, DUR_7D
            ),
            swallow
        );
    }

    // ------------------------------------------------------------------
    // Effects land before interactions
    // ------------------------------------------------------------------

    function test_ReserveFor_RecordsCollateralBeforePullingThePremium() public {
        _deposit(1_000e6);
        VaultStateProbe probe = new VaultStateProbe(vault);
        token.arm(address(probe), abi.encodeWithSignature("probe()"), false);

        vmPrank(buyer);
        note.create(address(stock), AMOUNT_5, LEVEL_80, DUR_7D);

        assertTrue(token.fired(), "the hook should have run mid-pull");
        assertEq(probe.calls(), 1, "the probe should have run exactly once");
        // Seen from inside the premium pull, the collateral is already on the books.
        // This is precisely what denies a re-entrant create a second free pass at the
        // same capacity.
        assertEq(probe.reservedAtCall(), LIABILITY, "liability must be reserved before the pull");
        assertEq(probe.depositsAtCall(), 1_000e6 + PREMIUM, "premium must be counted before the pull");
    }

    function test_SettlePayout_RecordsTheReleaseBeforePayingOut() public {
        _deposit(1_000e6);
        vmPrank(buyer);
        note.create(address(stock), AMOUNT_5, LEVEL_80, DUR_7D);

        vmWarp(T0 + DUR_7D + 1);
        feed.setPrice(50e8); // 400 floor - 250 current = 150 payout

        token.setHookSides(true, false); // only the payout leg, not the premium pull
        VaultStateProbe probe = new VaultStateProbe(vault);
        token.arm(address(probe), abi.encodeWithSignature("probe()"), false);

        note.settle(1);

        assertTrue(token.fired(), "the hook should have run during the payout");
        assertEq(probe.reservedAtCall(), 0, "the release must be recorded before the payout leaves");
        assertEq(probe.depositsAtCall(), 1_000e6 + PREMIUM - 150e6, "the payout must be off the books first");
    }

    // ------------------------------------------------------------------
    // A hook-bearing settlement token cannot break the accounting
    // ------------------------------------------------------------------

    /// @dev Regression. `create()` used to publish the note id only after the vault call,
    ///      so a re-entrant premium pull could claim the same id twice: the second create
    ///      overwrote the first note while both liabilities stayed reserved, leaving one
    ///      liability with no note able to release it.
    function test_Create_ReentrantTokenCannotReuseANoteId() public {
        _deposit(2_000e6);
        _armReentrantCreate(false);

        vmPrank(buyer);
        uint256 id = note.create(address(stock), AMOUNT_5, LEVEL_80, DUR_7D);

        assertEq(id, 1, "outer note id");
        assertTrue(token.fired(), "the hook should have run mid-pull");

        // Two ids consumed, two distinct live notes
        assertEq(note.nextId(), 2, "the re-entrant create must take the next id");
        (address owner1,,,,,,,,, ProtectionNote.Status status1) = note.notes(1);
        (address owner2,,,,,,,,, ProtectionNote.Status status2) = note.notes(2);
        assertEq(owner1, buyer, "note 1 belongs to the outer buyer");
        assertEq(owner2, address(token), "note 2 belongs to the re-entrant caller");
        assertEq(uint256(status1), uint256(ProtectionNote.Status.ACTIVE), "note 1 should be active");
        assertEq(uint256(status2), uint256(ProtectionNote.Status.ACTIVE), "note 2 should be active");

        // Every reserved wei is reachable by a note that can release it
        assertEq(vault.reserved(), 2 * LIABILITY, "both liabilities must be reserved against real ids");
        assertLe(
            vault.reserved(),
            vault.totalDeposits() - (vault.totalDeposits() * BUFFER_20) / 10_000,
            "inv1 must hold after a re-entrant create"
        );

        // And each note settles independently, releasing exactly its own liability
        vmWarp(T0 + DUR_7D + 1);
        feed.setPrice(50e8);
        note.settle(1);
        assertEq(vault.reserved(), LIABILITY, "note 1 must release only its own liability");
        note.settle(2);
        assertEq(vault.reserved(), 0, "note 2 must be able to release the rest");
    }

    /// @dev Regression. `reserveFor` used to run its capacity check and then pull the
    ///      premium before recording it, so a re-entrant pull could pass the same check
    ///      twice and reserve twice against one balance — breaching invariant 1.
    function test_Create_ReentrantPremiumPullCannotOutrunCapacity() public {
        // Deposit exactly enough for one note: usable == premium + liability
        _deposit(515.625e6);
        assertEq(vault.availableCapacity(), PREMIUM + LIABILITY, "capacity should fit exactly one note");

        _armReentrantCreate(true); // absorb the nested revert, so the outer create completes

        vmPrank(buyer);
        uint256 id = note.create(address(stock), AMOUNT_5, LEVEL_80, DUR_7D);

        assertEq(id, 1, "outer note id");
        assertTrue(token.fired(), "the hook should have run mid-pull");

        // The nested create was refused by capacity: one id, one reserved liability
        assertEq(note.nextId(), 1, "the re-entrant create must not have gone through");
        assertEq(vault.reserved(), LIABILITY, "exactly one liability may be reserved");
        assertLe(
            vault.reserved(),
            vault.totalDeposits() - (vault.totalDeposits() * BUFFER_20) / 10_000,
            "inv1 must hold: the nested reserve must not outrun capacity"
        );

        // The refused attempt collected nothing from the token
        assertEq(token.balanceOf(address(token)), 10_000e6, "the nested premium must never be collected");
        assertEq(vault.totalDeposits(), 515.625e6 + PREMIUM, "only the outer premium may join deposits");
        assertEq(token.balanceOf(address(vault)), vault.totalDeposits(), "custody must track accounting");
    }
}
