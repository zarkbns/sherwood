// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ScriptBase} from "./ScriptBase.sol";
import {SherwoodVault} from "../src/SherwoodVault.sol";
import {ProtectionNote} from "../src/ProtectionNote.sol";
import {DemoFeed} from "../src/testnet/DemoFeed.sol";
import {ProtectionMath} from "../src/ProtectionMath.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @title DemoCreate
/// @notice TESTNET ONLY. Full demo on-ramp in one broadcast: refresh the demo feed
///         price, fund the vault from the deployer wallet, and buy a 1-day protection
///         note (the demo tier) on the registered asset. Premium and liability come
///         out of the same wallet, so no second account is needed.
///
///         Required env: NOTE, VAULT, FEED (DemoFeed), ASSET (registered stock token)
///         Optional env:  DEMO_FUND (settlement-token raw, default 50e6),
///                        DEMO_AMOUNT (18 dec, default 0.1e18),
///                        DEMO_LEVEL (default 80e16),
///                        DEMO_PRICE (8 dec, default 250e8)
///
///         Run: forge script script/DemoCreate.s.sol --rpc-url <RPC_URL> --broadcast
contract DemoCreate is ScriptBase {
    function run() external {
        SherwoodVault vault = SherwoodVault(vmEnvAddress("VAULT"));
        ProtectionNote note = ProtectionNote(vmEnvAddress("NOTE"));
        DemoFeed feed = DemoFeed(vmEnvAddress("FEED"));
        address asset = vmEnvAddress("ASSET");
        uint256 fund = vmEnvUint("DEMO_FUND", 50e6);
        uint256 amount = vmEnvUint("DEMO_AMOUNT", 0.1e18);
        uint256 level = vmEnvUint("DEMO_LEVEL", 80e16);
        uint256 price = vmEnvUint("DEMO_PRICE", 250e8);
        IERC20 settlement = vault.token();

        vmStartBroadcast();
        feed.set(int256(price));
        vmStopBroadcast();

        // Quote after the price lands so it matches what create() will store. The approval
        // has to cover the deposit AND the premium: deposit pulls `fund` with transferFrom
        // from this same wallet, which would leave the allowance at zero for create() to
        // pull its premium from.
        (uint256 premiumUSD18,,) = note.quote(asset, amount, level, 1 days);
        uint256 premiumToken = ProtectionMath.toTokenUnits(premiumUSD18, settlement.decimals());

        vmStartBroadcast();
        settlement.approve(address(vault), fund + premiumToken);
        vault.deposit(fund);
        uint256 noteId = note.create(asset, amount, level, 1 days);
        vmStopBroadcast();

        (, , , , , uint256 expiry, , , , ) = note.notes(noteId);
        vmLog(string.concat("vault funded with ", vmToString(fund)));
        vmLog(string.concat("note ", vmToString(noteId), " created, expires ", vmToString(expiry)));
        vmLog("next: after expiry run DemoSettle.s.sol with NOTE_ID set");
    }
}
