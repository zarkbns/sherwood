// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {DeployConfig} from "../script/Config.s.sol";

/// @title DeployConfig settlement token
/// @notice The per-chain settlement config Sherwood deploys with: canonical USDG on
///         Robinhood Chain mainnet, the faucet-supplied MockUSDG on testnet, and a
///         `SETTLEMENT_TOKEN` override that keeps either network swappable without a code
///         change — while the testnet mock can never be pointed at mainnet.
contract DeployConfigTest is TestBase {
    uint256 constant MAINNET = 4663;
    uint256 constant TESTNET = 46630;

    address constant MAINNET_USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant TESTNET_MOCK_USDG = 0x8c4aa106a0A0d9ECAeD5C87e1AE766aa8Efbf006;

    DeployConfig internal config;

    function setUp() public {
        config = new DeployConfig();
    }

    function test_RobinhoodChainIds() public {
        assertEq(config.ROBINHOOD_MAINNET_CHAIN_ID(), MAINNET, "mainnet chain id");
        assertEq(config.ROBINHOOD_TESTNET_CHAIN_ID(), TESTNET, "testnet chain id");
    }

    function test_MainnetDefaultsToCanonicalUsdg() public {
        assertEq(config.get(MAINNET).settlementToken, MAINNET_USDG, "mainnet default");
        assertEq(config.settlementToken(MAINNET, address(0)), MAINNET_USDG, "mainnet needs no override");
    }

    function test_TestnetDefaultsToMockUsdg() public {
        assertEq(config.get(TESTNET).settlementToken, TESTNET_MOCK_USDG, "testnet default");
        assertEq(config.settlementToken(TESTNET, address(0)), TESTNET_MOCK_USDG, "testnet needs no override");
    }

    function test_BufferIsPerSpecOnBothNetworks() public {
        assertEq(config.get(MAINNET).bufferBps, 2000, "mainnet 20% reserve");
        assertEq(config.get(TESTNET).bufferBps, 2000, "testnet 20% reserve");
    }

    function test_OverrideWinsOnBothNetworks() public {
        address replacement = 0x1111111111111111111111111111111111111111;
        assertEq(config.settlementToken(MAINNET, replacement), replacement, "production token stays configurable");
        assertEq(config.settlementToken(TESTNET, replacement), replacement, "testnet token stays configurable");
    }

    function test_ExplicitPairingIsAccepted() public {
        assertEq(config.settlementToken(MAINNET, MAINNET_USDG), MAINNET_USDG, "canonical USDG on mainnet");
        assertEq(config.settlementToken(TESTNET, TESTNET_MOCK_USDG), TESTNET_MOCK_USDG, "mock on testnet");
    }

    function test_MockIsRecognised() public {
        assertTrue(config.isTestnetMockToken(TESTNET_MOCK_USDG), "mock flagged");
        assertFalse(config.isTestnetMockToken(MAINNET_USDG), "canonical USDG is not the mock");
        assertFalse(config.isTestnetMockToken(address(0)), "zero is not the mock");
    }

    function test_MockOnMainnetReverts() public {
        vmExpectRevert(DeployConfig.MockTokenOnMainnet.selector);
        config.settlementToken(MAINNET, TESTNET_MOCK_USDG);
    }

    function test_ChainWithoutDefaultOrOverrideReverts() public {
        assertEq(config.get(1).settlementToken, address(0), "no config for other chains");
        vmExpectRevert(DeployConfig.NoSettlementToken.selector);
        config.settlementToken(1, address(0));
    }
}
