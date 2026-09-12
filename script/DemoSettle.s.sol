// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ScriptBase} from "./ScriptBase.sol";
import {ProtectionNote} from "../src/ProtectionNote.sol";
import {DemoFeed} from "../src/testnet/DemoFeed.sol";

/// @title DemoSettle
/// @notice TESTNET ONLY. The off-ramp: crashes the demo feed price to
///         DEMO_SETTLE_PRICE (8 decimals, default $100 — below the floor of a note
///         created at the DemoCreate default $250 with an 80% level) and settles the
///         note. Settlement is permissionless, so anyone can run this after expiry.
///
///         Required env: NOTE, FEED (DemoFeed)
///         Optional env:  NOTE_ID (default 1), DEMO_SETTLE_PRICE (8 dec, default 100e8)
///
///         Run: forge script script/DemoSettle.s.sol --rpc-url <RPC_URL> --broadcast
contract DemoSettle is ScriptBase {
    function run() external {
        ProtectionNote note = ProtectionNote(vmEnvAddress("NOTE"));
        DemoFeed feed = DemoFeed(vmEnvAddress("FEED"));
        uint256 noteId = vmEnvUint("NOTE_ID", 1);
        uint256 settlePrice = vmEnvUint("DEMO_SETTLE_PRICE", 100e8);

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
