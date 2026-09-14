// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {ProtectionOracle} from "../src/ProtectionOracle.sol";
import {ProtectionNote} from "../src/ProtectionNote.sol";
import {SherwoodVault} from "../src/SherwoodVault.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {MockAggregator, MockERC20, MockUSDG} from "./Mocks.sol";

/// @title MockUSDG faucet economics
/// @notice Pins the published behavior of the testnet settlement token: 1,000 tokens per
///         address per 24 hours, once per address, and no other open supply after
///         `lockMint()`. The same claims were made live on Robinhood Chain testnet on
///         2026-09-13 (claim 0x6e8c867dfb0f9b2b057bac9cbe6fc82979dac7ec701f1b7cdb0af1bc8a4122e6
///         minted 1_000_000_000; the immediate retry reverted `FaucetCooldown`); this
///         suite keeps the numbers honest offline.
contract MockUSDGFaucetTest is TestBase {
    uint256 constant T0 = 1_700_000_000;
    uint256 constant DAY = 24 hours;

    MockUSDG internal token;
    address internal alice = vmMakeAddr("alice");
    address internal bob = vmMakeAddr("bob");

    event Faucet(address indexed to, uint256 amount);

    function setUp() public {
        vmWarp(T0);
        token = new MockUSDG();
    }

    function test_PublishedEconomics() public {
        assertEq(token.FAUCET_AMOUNT(), 1000e6, "1,000 MockUSDG per claim");
        assertEq(token.FAUCET_COOLDOWN(), DAY, "one claim per 24h");
        assertEq(uint256(token.decimals()), 6, "6 decimals, like USDG");
        assertEq(token.symbol(), "USDG", "symbol");
    }

    function test_Faucet_Mints1000ToTheCaller() public {
        vmExpectEmit(true, true, true, true);
        emit Faucet(alice, 1000e6);

        vmPrank(alice);
        token.faucet();

        assertEq(token.balanceOf(alice), 1000e6, "balance after one claim");
        assertEq(token.totalSupply(), 1000e6, "faucet is the only minter here");
        assertEq(token.lastFaucetAt(alice), T0, "claim stamped");
        assertEq(token.faucetCooldownRemaining(alice), DAY, "full cooldown starts");
    }

    function test_Faucet_RevertsSecondClaimWithinCooldown() public {
        vmPrank(alice);
        token.faucet();

        vmExpectRevertData(abi.encodeWithSelector(MockUSDG.FaucetCooldown.selector, T0 + DAY));
        vmPrank(alice);
        token.faucet();

        assertEq(token.balanceOf(alice), 1000e6, "rejected claim minted nothing");
    }

    function test_Faucet_ClaimsAgainOnceCooldownElapses() public {
        vmPrank(alice);
        token.faucet();

        vmWarp(T0 + DAY);
        assertEq(token.faucetCooldownRemaining(alice), 0, "claimable at exactly nextAt");

        vmPrank(alice);
        token.faucet();
        assertEq(token.balanceOf(alice), 2000e6, "second daily claim");
    }

    function test_Faucet_CooldownIsPerAddress() public {
        vmPrank(alice);
        token.faucet();

        assertEq(token.faucetCooldownRemaining(bob), 0, "bob untouched by alice's claim");
        vmPrank(bob);
        token.faucet();

        assertEq(token.balanceOf(bob), 1000e6, "bob claims while alice is cooling down");
        assertEq(token.faucetCooldownRemaining(alice), DAY, "alice unaffected");
    }

    function test_Faucet_CooldownCountsDown() public {
        vmPrank(alice);
        token.faucet();

        vmWarp(T0 + 6 hours);
        assertEq(token.faucetCooldownRemaining(alice), 18 hours, "18h left");
    }

    function test_LockMint_ClosesPublicMint_KeepsFaucetOpen() public {
        token.lockMint();
        assertTrue(token.mintLocked(), "mint locked");

        vmExpectRevert(MockUSDG.NotAdmin.selector);
        vmPrank(alice);
        token.mint(alice, 1e6);

        vmPrank(alice);
        token.faucet();
        assertEq(token.balanceOf(alice), 1000e6, "faucet stays open after the lock");
    }
}

/// @title MockUSDG as the testnet settlement token
/// @notice Walks the protocol's three money paths — vault reserve, buyer premium,
///         settlement payout — funded only by faucet claims on a locked MockUSDG, on the
///         exact terms of the testnet demo: 0.1 TSLA at a $250 entry, 80% level, 1 day
///         (225 bps -> $0.5625 premium, $20.00 floor).
contract MockUSDGSettlementTest is TestBase {
    uint256 constant T0 = 1_700_000_000;
    uint256 constant ENTRY_250 = 250e8;
    uint256 constant SETTLE_100 = 100e8;
    uint256 constant SETTLE_300 = 300e8;
    uint256 constant AMOUNT_01 = 0.1e18;
    uint256 constant LEVEL_80 = 80e16;
    uint256 constant DUR_1D = 1 days;

    uint256 constant PREMIUM_0_5625 = 562_500; // $25 x 225 bps = $0.5625 -> 6 dec
    uint256 constant FLOOR_20 = 20e6; // 0.1 x $250 x 0.8 = $20 -> 6 dec
    uint256 constant PAYOUT_10 = 10e6; // floor $20 - current $10 = $10 -> 6 dec

    MockUSDG internal token;
    MockERC20 internal stock;
    AssetRegistry internal registry;
    ProtectionOracle internal oracle;
    SherwoodVault internal vault;
    ProtectionNote internal note;
    MockAggregator internal feed;

    address internal depositor = vmMakeAddr("depositor");
    address internal buyer = vmMakeAddr("buyer");
    address internal keeper = vmMakeAddr("keeper");

    function setUp() public {
        vmWarp(T0);
        token = new MockUSDG();
        token.lockMint(); // as deployed on 46630: public mint closed, faucet is the open supply

        stock = new MockERC20("Tesla", "TSLA", 18);
        registry = new AssetRegistry();
        // Testnet 46630 publishes no L2 sequencer uptime feed, so the oracle runs with
        // the check off and the per-asset staleness guard alone.
        oracle = new ProtectionOracle(IAggregatorV3(address(0)), 0);
        vault = new SherwoodVault(IERC20(address(token)), 2000);
        note = new ProtectionNote(registry, oracle, vault);
        vault.setNoteContract(address(note));

        feed = new MockAggregator(8);
        feed.setPrice(int256(ENTRY_250));
        registry.registerAsset(address(stock), "TSLA", feed, 72 hours);
    }

    function _claim(address who) internal {
        vmPrank(who);
        token.faucet();
    }

    function _fundVaultFromFaucet(uint256 amount) internal {
        _claim(depositor);
        vmStartPrank(depositor);
        token.approve(address(vault), amount);
        vault.deposit(amount);
        vmStopPrank();
    }

    function _fundBuyer() internal {
        _claim(buyer);
        stock.mint(buyer, 10e18); // position guard: the buyer must hold what they protect
        vmStartPrank(buyer);
        token.approve(address(vault), 1000e6);
        vmStopPrank();
    }

    function test_Quote_PremiumAndFloorInTokenUnits() public {
        (uint256 premiumUSD18, uint256 protectedUSD18,) = note.quote(address(stock), AMOUNT_01, LEVEL_80, DUR_1D);
        assertEq(premiumUSD18, 562_500e12, "premium stays USD-18");
        assertEq(protectedUSD18, 20e18, "floor stays USD-18");
        // The 6-decimal conversion is what the vault actually moves: /1e12.
        assertEq(premiumUSD18 / 1e12, PREMIUM_0_5625, "premium in MockUSDG");
        assertEq(protectedUSD18 / 1e12, FLOOR_20, "liability in MockUSDG");
    }

    function test_Payout_DownsideSettlesInMockUSDG() public {
        _fundVaultFromFaucet(500e6);
        _fundBuyer();

        uint256 buyerBefore = token.balanceOf(buyer);
        vmPrank(buyer);
        uint256 id = note.create(address(stock), AMOUNT_01, LEVEL_80, DUR_1D);

        // Premium collected and collateral reserved atomically, in 6-decimal units.
        assertEq(buyerBefore - token.balanceOf(buyer), PREMIUM_0_5625, "premium debited");
        assertEq(vault.reserved(), FLOOR_20, "liability reserved");
        assertEq(vault.totalDeposits(), 500e6 + PREMIUM_0_5625, "premium joins deposits");
        assertEq(token.balanceOf(address(vault)), 500e6 + PREMIUM_0_5625, "invariant 5: reserved collateral is held");
        assertGe(token.balanceOf(address(vault)), vault.reserved(), "invariant 5: vault never short of liability");

        vmWarp(T0 + DUR_1D + 1);
        feed.setPrice(int256(SETTLE_100));
        vmPrank(keeper);
        note.settle(id);

        assertEq(token.balanceOf(buyer), buyerBefore - PREMIUM_0_5625 + PAYOUT_10, "payout max(0, floor - current)");
        assertEq(vault.reserved(), 0, "liability released");
        assertEq(vault.totalDeposits(), 500e6 + PREMIUM_0_5625 - PAYOUT_10, "payout leaves deposits");
        assertEq(token.balanceOf(address(vault)), 500e6 + PREMIUM_0_5625 - PAYOUT_10, "custody matches accounting");
    }

    function test_Payout_NoPayoutWhenPriceHoldsAboveFloor() public {
        _fundVaultFromFaucet(500e6);
        _fundBuyer();

        uint256 buyerBefore = token.balanceOf(buyer);
        vmPrank(buyer);
        uint256 id = note.create(address(stock), AMOUNT_01, LEVEL_80, DUR_1D);

        vmWarp(T0 + DUR_1D + 1);
        feed.setPrice(int256(SETTLE_300));
        vmPrank(keeper);
        note.settle(id);

        assertEq(token.balanceOf(buyer), buyerBefore - PREMIUM_0_5625, "no payout above the floor");
        assertEq(vault.reserved(), 0, "liability released");
        assertEq(vault.totalDeposits(), 500e6 + PREMIUM_0_5625, "premium retained");
    }

    function test_Capacity_CannotOverReserveBeyondOneClaimOfCollateral() public {
        // One claim funds the vault with 1,000 MockUSDG, so capacity is 800 after the 20%
        // buffer. A $800 floor plus its premium needs 822.5, which must be rejected before
        // anything is collected — faucet-claimed balances can never create uncovered
        // liability.
        _fundVaultFromFaucet(1000e6);
        _fundBuyer();

        uint256 buyerBefore = token.balanceOf(buyer);
        vmExpectRevert(SherwoodVault.InsufficientCapacity.selector);
        vmPrank(buyer);
        note.create(address(stock), 4e18, LEVEL_80, DUR_1D);

        assertEq(token.balanceOf(buyer), buyerBefore, "no premium on a rejected note");
        assertEq(vault.reserved(), 0, "no liability reserved");
        assertEq(vault.totalDeposits(), 1000e6, "deposits untouched");
    }
}
