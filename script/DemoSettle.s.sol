// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ScriptBase} from "./ScriptBase.sol";
import {ProtectionNote} from "../src/ProtectionNote.sol";
import {DemoFeed} from "../src/testnet/DemoFeed.sol";

/// @title DemoSettle
/// @notice TESTNET ONLY. The off-ramp: moves the demo feed price to DEMO_SETTLE_PRICE
///         (8 decimals) and settles the note, proving one of the two settlement branches:
///         a price below the floor pays out, a price at or above it pays nothing while
///         the reserve still releases. Settlement is permissionless, so anyone can run
///         this after expiry.
///
///         Required env: NOTE, FEED (DemoFeed), DEMO_SETTLE_PRICE (8 dec)
///         Optional env:  NOTE_ID (default 1)
///
///         DEMO_SETTLE_PRICE is demanded, not defaulted: the price picked here decides
///         which branch the run proves, and a silent default once chose a price that
///         would have paid a note whose floor sat above it — the exact opposite of the
///         zero-payout boundary that note was created to demonstrate.
///
///         Run: forge script script/DemoSettle.s.sol --rpc-url <RPC_URL> --broadcast
contract DemoSettle is ScriptBase {
    function run() external {
        ProtectionNote note = ProtectionNote(vmEnvAddress("NOTE"));
        DemoFeed feed = DemoFeed(vmEnvAddress("FEED"));
        uint256 noteId = vmEnvUint("NOTE_ID", 1);
        uint256 settlePrice = vmEnvUintRequired("DEMO_SETTLE_PRICE");

        // Rejected before any broadcast: a junk price would strand the shared demo feed
        // at a value every later run has to undo.
        require(settlePrice > 0, "DEMO_SETTLE_PRICE must be a positive 8-decimal price");

        require(note.isSettlable(noteId), "note not settlable yet (1-day demo tier expires 24h after create)");

        vmStartBroadcast();
        feed.set(int256(settlePrice));
        note.settle(noteId);
        vmStopBroadcast();

        (, , , , , , , , , ProtectionNote.Status status) = note.notes(noteId);
        vmLog(string.concat("settled at ", vmToString(int256(settlePrice))));
        vmLog(string.concat("status: ", vmToString(uint256(uint8(status)))));
    }
}
