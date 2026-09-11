// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title DeployConfig
/// @notice ChainId -> deployment constants. Sherwood targets Robinhood Chain only.
///         The canonical USDG address is verified for mainnet; the testnet USDG
///         address is not published in the Robinhood docs yet, so testnet resolves
///         SETTLEMENT_TOKEN from the environment (confirm on
///         explorer.testnet.chain.robinhood.com at deploy).
contract DeployConfig {
    // Robinhood Chain chain IDs, per docs.robinhood.com/chain/connecting.
    uint256 public constant ROBINHOOD_MAINNET_CHAIN_ID = 4663;
    uint256 public constant ROBINHOOD_TESTNET_CHAIN_ID = 46630;

    // Canonical USDG (Paxos Global Dollar) on Robinhood Chain mainnet, per
    // docs.robinhood.com/chain/contracts. Decimals must be read from the token
    // on-chain; the vault does this at runtime.
    address public constant ROBINHOOD_MAINNET_USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;

    // Spec §2: 20% unencumbered reserve, owner-adjustable up to 5000 bps.
    uint256 public constant DEFAULT_BUFFER_BPS = 2000;

    struct ChainConfig {
        address settlementToken; // address(0) -> resolve via SETTLEMENT_TOKEN env
        uint256 bufferBps;
    }

    function get(uint256 chainId) public pure returns (ChainConfig memory) {
        if (chainId == ROBINHOOD_MAINNET_CHAIN_ID) {
            return ChainConfig({settlementToken: ROBINHOOD_MAINNET_USDG, bufferBps: DEFAULT_BUFFER_BPS});
        }
        return ChainConfig({settlementToken: address(0), bufferBps: DEFAULT_BUFFER_BPS});
    }
}
