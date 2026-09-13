// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title DeployConfig
/// @notice ChainId -> deployment constants. Sherwood targets Robinhood Chain only.
///         The settlement token is per-chain config: canonical USDG on mainnet, the
///         faucet-supplied MockUSDG on testnet. Either default can be overridden at
///         deploy time with `SETTLEMENT_TOKEN`, so an address swap (a Paxos migration
///         on mainnet, a replacement mock on testnet) never needs a code change.
contract DeployConfig {
    // Robinhood Chain chain IDs, per docs.robinhood.com/chain/connecting.
    uint256 public constant ROBINHOOD_MAINNET_CHAIN_ID = 4663;
    uint256 public constant ROBINHOOD_TESTNET_CHAIN_ID = 46630;

    // Canonical USDG (Paxos Global Dollar) on Robinhood Chain mainnet, per
    // docs.robinhood.com/chain/contracts. Decimals must be read from the token
    // on-chain; the vault does this at runtime.
    address public constant ROBINHOOD_MAINNET_USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;

    /// @notice Testnet settlement token: MockUSDG ("Mock USDG", symbol "USDG", 6 decimals).
    ///
    /// Verified 2026-09-13 against the source-verified deploy at
    /// explorer.testnet.chain.robinhood.com (`src/mocks/MockUSDG.sol`, solc 0.8.28,
    /// optimizer 200 runs) and by calling it live on 46630:
    ///   FAUCET_AMOUNT = 1000e6, FAUCET_COOLDOWN = 1 days, decimals() = 6,
    ///   mintLocked() = true, admin = 0x0b64b35c6dd23944d6d4029864d2ca2aa1b66422.
    ///   One live `faucet()` claim minted exactly 1_000_000_000 (1,000 USDG) and the
    ///   immediate second claim reverted `FaucetCooldown(lastFaucetAt + 86400)`.
    ///
    /// Why not the canonical testnet USDG at 0x7E955252E15c84f5768B83c41a71F9eba181802F
    /// (verified 2026-09-12, Paxos UUPS proxy)? It is real and identical in interface,
    /// but the Robinhood testnet USDG drip never reached protocol wallets, which left
    /// the premium/vault/payout path unexercisable. MockUSDG has a public faucet, so
    /// every testnet flow can be funded and settled end to end.
    ///
    /// TESTNET ONLY. Its admin can still mint and burn freely, so testnet balances are
    /// not sound money — never point a mainnet deployment at this token.
    address public constant ROBINHOOD_TESTNET_USDG = 0x8c4aa106a0A0d9ECAeD5C87e1AE766aa8Efbf006;

    // Spec §2: 20% unencumbered reserve, owner-adjustable up to 5000 bps.
    uint256 public constant DEFAULT_BUFFER_BPS = 2000;

    struct ChainConfig {
        address settlementToken; // address(0) -> chain has no default, SETTLEMENT_TOKEN is required
        uint256 bufferBps;
    }

    function get(uint256 chainId) public pure returns (ChainConfig memory) {
        if (chainId == ROBINHOOD_MAINNET_CHAIN_ID) {
            return ChainConfig({settlementToken: ROBINHOOD_MAINNET_USDG, bufferBps: DEFAULT_BUFFER_BPS});
        }
        if (chainId == ROBINHOOD_TESTNET_CHAIN_ID) {
            return ChainConfig({settlementToken: ROBINHOOD_TESTNET_USDG, bufferBps: DEFAULT_BUFFER_BPS});
        }
        return ChainConfig({settlementToken: address(0), bufferBps: DEFAULT_BUFFER_BPS});
    }

    /// @notice Settlement token for a chain: the `SETTLEMENT_TOKEN` override when one
    ///         was supplied, otherwise the chain default. Returns address(0) for chains
    ///         with neither, which callers must reject.
    function resolveSettlementToken(uint256 chainId, address envOverride) public pure returns (address) {
        if (envOverride != address(0)) return envOverride;
        return get(chainId).settlementToken;
    }

    /// @notice True for the capped testnet faucet token. Mainnet deployments must never
    ///         settle real collateral against it: the mock's admin can mint at will.
    function isTestnetMockToken(address token) public pure returns (bool) {
        return token == ROBINHOOD_TESTNET_USDG;
    }

    /// @notice The chain's settlement token with the deployment guards applied. Used by
    ///         script/Deploy.s.sol so the pairing rules are testable in isolation.
    function settlementToken(uint256 chainId, address envOverride) public pure returns (address) {
        address token = resolveSettlementToken(chainId, envOverride);
        if (token == address(0)) revert NoSettlementToken();
        if (chainId == ROBINHOOD_MAINNET_CHAIN_ID && isTestnetMockToken(token)) revert MockTokenOnMainnet();
        return token;
    }

    error NoSettlementToken();
    error MockTokenOnMainnet();
}
