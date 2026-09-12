// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ScriptBase} from "./ScriptBase.sol";
import {DemoFeed} from "../src/testnet/DemoFeed.sol";

/// @title DemoFeed deployer
/// @notice TESTNET ONLY. Deploys one owner-set DemoFeed per supported symbol so the
///         demo can register assets on a chain where Chainlink publishes no feeds.
///         Initial prices come from DEMO_PRICE_<SYM> env (8 decimals), default $100.
///         Run: forge script script/DemoFeed.s.sol --rpc-url <RPC_URL> --broadcast
contract DeployDemoFeeds is ScriptBase {
    string[] internal SYMBOLS = ["TSLA", "AMZN", "NFLX", "PLTR", "AMD"];

    function run() external {
        vmStartBroadcast();
        for (uint256 i = 0; i < SYMBOLS.length; i++) {
            string memory symbol = SYMBOLS[i];
            uint256 price = vmEnvUint(string.concat("DEMO_PRICE_", symbol), 100e8);
            DemoFeed feed = new DemoFeed(8, int256(price));
            vmLog(string.concat("DemoFeed ", symbol, ": ", vmToString(address(feed))));
        }
        vmStopBroadcast();
    }
}
