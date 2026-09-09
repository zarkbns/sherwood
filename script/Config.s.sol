// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title DeployConfig
/// @notice ChainId -> deployment constants (spec §7). Arbitrum One is the only chain
///         with a known settlement token today; Arbitrum Sepolia and Robinhood Chain
///         testnet resolve SETTLEMENT_TOKEN from the environment in Deploy.s.sol until
///         official addresses are verified.
contract DeployConfig {
    // Canonical USDC (6 decimals) on Arbitrum One.
    address public constant ARBITRUM_ONE_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    // Spec §2: 20% unencumbered reserve, owner-adjustable up to 5000 bps.
    uint256 public constant DEFAULT_BUFFER_BPS = 2000;

    struct ChainConfig {
        address settlementToken; // address(0) -> resolve via SETTLEMENT_TOKEN env
        uint256 bufferBps;
    }

    function get(uint256 chainId) public pure returns (ChainConfig memory) {
        if (chainId == 42161) {
            return ChainConfig({settlementToken: ARBITRUM_ONE_USDC, bufferBps: DEFAULT_BUFFER_BPS});
        }
        return ChainConfig({settlementToken: address(0), bufferBps: DEFAULT_BUFFER_BPS});
    }
}
