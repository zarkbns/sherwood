// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {MockAggregator, MockERC20} from "./Mocks.sol";

// Diagnostic only: what does an EXTERNAL call to getAsset() actually return on the wire?
// Internal reads (like every existing test uses) never exercise the external ABI shape.
// 224 bytes = flat 7-word tuple (string head, feed, staleness, active, registered, len, "TSLA").
// 256 bytes = 8-word wrapped form (outer 0x20 pointer + the flat tuple after it).
contract ReproGetAssetTest is TestBase {
    function test_externalGetAsset_rawReturnShape() public {
        AssetRegistry registry = new AssetRegistry();
        MockAggregator feed = new MockAggregator(8);
        address token = address(new MockERC20("Tesla", "TSLA", 18));
        registry.registerAsset(token, "TSLA", IAggregatorV3(address(feed)), 0);

        (bool ok, bytes memory ret) = address(registry).call(
            abi.encodeCall(registry.getAsset, (token))
        );
        assertTrue(ok, "external call failed");
        assertEq(ret.length, 256, "len: 224=flat tuple, 256=wrapped with outer pointer");

        bytes32 word0;
        assembly {
            word0 := mload(add(ret, 32))
        }
        // 0x20 in word0 means the data opens with a dynamic pointer before the tuple head.
        assertEq(uint256(word0), 0x20, "word0: 0x20 = wrapped form, 0xa0 = flat form");
    }
}
