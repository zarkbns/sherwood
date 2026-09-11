// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {Ownable} from "../src/Ownable.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {MockAggregator} from "./Mocks.sol";

contract AssetRegistryTest is TestBase {
    AssetRegistry internal registry;
    MockAggregator internal feed;

    address internal tsLA = vmMakeAddr("TSLA token");
    address internal amzn = vmMakeAddr("AMZN token");

    function setUp() public {
        registry = new AssetRegistry();
        feed = new MockAggregator(8);
    }

    function test_RegisterAsset_StoresAllFields() public {
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 72 hours);

        AssetRegistry.Asset memory asset = registry.getAsset(tsLA);
        assertEq(asset.symbol, "TSLA", "symbol mismatch");
        assertEq(address(asset.feed), address(feed), "feed mismatch");
        assertEq(asset.maxStaleness, 72 hours, "staleness mismatch");
        assertTrue(asset.active, "should be active on registration");
        assertTrue(asset.registered, "should be registered");
        assertTrue(registry.isSupported(tsLA), "should be supported");
    }

    function test_RegisterAsset_ZeroStalenessGetsDefault() public {
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 0);
        assertEq(registry.getAsset(tsLA).maxStaleness, registry.DEFAULT_STALENESS(), "default staleness");
    }

    function test_RegisterAsset_TracksList() public {
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 72 hours);
        registry.registerAsset(amzn, "AMZN", IAggregatorV3(address(feed)), 72 hours);

        address[] memory assets = registry.allAssets();
        assertEq(assets.length, 2, "should track two assets");
        assertEq(assets[0], tsLA, "first asset wrong");
        assertEq(assets[1], amzn, "second asset wrong");
    }

    function test_RegisterAsset_RevertsOnDuplicate() public {
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 72 hours);
        vmExpectRevert(AssetRegistry.AlreadyRegistered.selector);
        registry.registerAsset(tsLA, "TSLA dup", IAggregatorV3(address(feed)), 72 hours);
    }

    function test_RegisterAsset_RevertsOnZeroToken() public {
        vmExpectRevert(AssetRegistry.ZeroAddress.selector);
        registry.registerAsset(address(0), "ZERO", IAggregatorV3(address(feed)), 72 hours);
    }

    function test_RegisterAsset_RevertsOnZeroFeed() public {
        vmExpectRevert(AssetRegistry.ZeroAddress.selector);
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(0)), 72 hours);
    }

    function test_RegisterAsset_RevertsOnStalenessAboveCap() public {
        vmExpectRevert(AssetRegistry.StalenessTooHigh.selector);
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 7 days + 1);
    }

    function test_RegisterAsset_RevertsWhenNotOwner() public {
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(Ownable.Unauthorized.selector);
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 72 hours);
    }

    function test_SetAssetActive_RevertsWhenNotOwner() public {
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 72 hours);
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(Ownable.Unauthorized.selector);
        registry.setAssetActive(tsLA, false);
    }

    function test_SetAssetActive_DisablesNewNotesButKeepsRegistration() public {
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 72 hours);

        registry.setAssetActive(tsLA, false);
        assertFalse(registry.isSupported(tsLA), "should not be supported when disabled");
        assertTrue(registry.getAsset(tsLA).registered, "still registered");
    }

    function test_SetAssetActive_RoundTrip() public {
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 72 hours);
        registry.setAssetActive(tsLA, false);
        registry.setAssetActive(tsLA, true);
        assertTrue(registry.isSupported(tsLA), "should be re-enabled");
    }

    function test_SetAssetActive_RevertsOnUnregistered() public {
        vmExpectRevert(AssetRegistry.NotRegistered.selector);
        registry.setAssetActive(amzn, false);
    }

    function test_SetAssetFeed_RotatesFeed() public {
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 72 hours);

        MockAggregator newFeed = new MockAggregator(8);
        registry.setAssetFeed(tsLA, IAggregatorV3(address(newFeed)));
        assertEq(address(registry.getAsset(tsLA).feed), address(newFeed), "feed not rotated");
    }

    function test_SetAssetFeed_RevertsWhenNotOwner() public {
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 72 hours);
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(Ownable.Unauthorized.selector);
        registry.setAssetFeed(tsLA, IAggregatorV3(address(feed)));
    }

    function test_SetAssetFeed_RevertsOnUnregistered() public {
        vmExpectRevert(AssetRegistry.NotRegistered.selector);
        registry.setAssetFeed(amzn, IAggregatorV3(address(feed)));
    }

    function test_SetAssetFeed_RevertsOnZeroFeed() public {
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 72 hours);
        vmExpectRevert(AssetRegistry.ZeroAddress.selector);
        registry.setAssetFeed(tsLA, IAggregatorV3(address(0)));
    }

    function test_UnregisteredAsset_IsNotSupported() public {
        assertFalse(registry.isSupported(amzn), "unregistered should be unsupported");
    }

    function test_TransferOwnership_NewOwnerCanAdmin() public {
        address newOwner = vmMakeAddr("new owner");
        registry.transferOwnership(newOwner);

        vmPrank(newOwner);
        registry.registerAsset(tsLA, "TSLA", IAggregatorV3(address(feed)), 72 hours);
        assertTrue(registry.isSupported(tsLA), "new owner should be able to register");
    }

    function test_TransferOwnership_RevertsOnZero() public {
        vmExpectRevert(Ownable.InvalidOwner.selector);
        registry.transferOwnership(address(0));
    }

    function test_TransferOwnership_RevertsWhenNotOwner() public {
        vmPrank(vmMakeAddr("attacker"));
        vmExpectRevert(Ownable.Unauthorized.selector);
        registry.transferOwnership(vmMakeAddr("anyone"));
    }
}
