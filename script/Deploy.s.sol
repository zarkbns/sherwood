// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployConfig} from "./Config.s.sol";
import {ScriptBase} from "./ScriptBase.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {ProtectionOracle} from "../src/ProtectionOracle.sol";
import {ProtectionMath} from "../src/ProtectionMath.sol";
import {SherwoodVault} from "../src/SherwoodVault.sol";
import {ProtectionNote} from "../src/ProtectionNote.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @title Deploy
/// @notice Full protocol deployment, chain-configured via DeployConfig (spec §7).
///         Sherwood targets Robinhood Chain: the settlement token defaults to
///         canonical USDG on mainnet and the faucet-supplied MockUSDG on testnet, and
///         `SETTLEMENT_TOKEN` overrides either. Stock tokens and Chainlink feeds are
///         read from the environment so feed addresses can be verified per chain at
///         deploy time instead of baked in.
///
///         Required when the chain has no configured token:
///           SETTLEMENT_TOKEN=0x...
///         Optional:
///           SETTLEMENT_TOKEN=0x...   override the chain default (both networks)
///           SEQUENCER_UPTIME_FEED=0x...   Chainlink L2 sequencer uptime feed. Read from
///                                         docs.chain.link at deploy time and never
///                                         hardcoded; unset leaves the check off, which
///                                         is the correct state for a chain that
///                                         publishes no feed (testnet 46630 today).
///           SEQUENCER_GRACE_PERIOD=3600   seconds after restart before prices are trusted
///           TOKEN_TSLA=0x... FEED_TSLA=0x...   per-asset registration (also AMZN,
///                                                NFLX, PLTR, AMD)
///
///         Run: forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast
contract Deploy is ScriptBase {
    string[] internal SYMBOLS = ["TSLA", "AMZN", "NFLX", "PLTR", "AMD"];

    /// @dev Chainlink's recommended window after an L2 sequencer restart: the update
    ///      backlog lands in a burst, so early rounds can carry pre-outage prices.
    uint256 internal constant DEFAULT_SEQUENCER_GRACE_PERIOD = 1 hours;

    function run() external {
        uint256 chainId = block.chainid;
        DeployConfig config = new DeployConfig();
        DeployConfig.ChainConfig memory cfg = config.get(chainId);

        address settlement = config.settlementToken(chainId, vmEnvAddressOpt("SETTLEMENT_TOKEN"));
        // MockTokenOnMainnet covers the dangerous case: the testnet mock has an admin
        // that can mint unlimited balance, so reserving real collateral against it would
        // misstate what backs a note.
        vmLog(string.concat("chain: ", vmToString(chainId)));
        vmLog(string.concat("settlement token: ", vmToString(settlement),
            config.isTestnetMockToken(settlement) ? " (MockUSDG - testnet faucet, 1,000 per address per 24h)"
                : " (canonical USDG)"));

        // Pre-flight: the vault prices every premium, reserve and payout in this token's
        // units, so a token with no code or unsupported decimals must fail here rather
        // than after four contracts have been deployed against it.
        require(settlement.code.length > 0, "settlement token has no code at this address");
        uint8 settlementDecimals = IERC20(settlement).decimals();
        require(settlementDecimals <= 18, "settlement token decimals above 18 are unsupported");
        vmLog(string.concat("settlement decimals: ", vmToString(uint256(settlementDecimals))));

        vmStartBroadcast();

        AssetRegistry registry = new AssetRegistry();
        address uptimeFeed = vmEnvAddressOpt("SEQUENCER_UPTIME_FEED");
        uint256 gracePeriod = vmEnvUint("SEQUENCER_GRACE_PERIOD", DEFAULT_SEQUENCER_GRACE_PERIOD);
        ProtectionOracle oracle = new ProtectionOracle(IAggregatorV3(uptimeFeed), gracePeriod);
        SherwoodVault vault = new SherwoodVault(IERC20(settlement), cfg.bufferBps);
        ProtectionNote note = new ProtectionNote(registry, oracle, vault);

        // Vault accepts reserve/settle calls only from the note contract.
        vault.setNoteContract(address(note));

        _registerAssets(registry);

        vmStopBroadcast();

        // Post-deploy sanity: refuse to report success on a miswire.
        require(address(vault.noteContract()) == address(note), "note contract not wired");
        require(address(note.registry()) == address(registry), "registry not wired");
        require(address(note.oracle()) == address(oracle), "oracle not wired");
        require(address(note.vault()) == address(vault), "vault not wired");
        require(address(vault.token()) == settlement, "settlement token mismatch");
        require(vault.bufferBps() == cfg.bufferBps, "buffer mismatch");
        require(address(oracle.sequencerUptimeFeed()) == uptimeFeed, "sequencer uptime feed not wired");
        require(oracle.sequencerGracePeriod() == gracePeriod, "sequencer grace period not wired");

        vmLog("deployed:");
        vmLog(string.concat("  AssetRegistry:    ", vmToString(address(registry))));
        vmLog(string.concat("  ProtectionOracle: ", vmToString(address(oracle))));
        vmLog(string.concat("  SherwoodVault:    ", vmToString(address(vault))));
        vmLog(string.concat("  ProtectionNote:   ", vmToString(address(note))));
        if (uptimeFeed == address(0)) {
            vmLog("sequencer uptime check: OFF (no SEQUENCER_UPTIME_FEED - set it if this chain publishes a feed)");
        } else {
            vmLog(string.concat(
                "sequencer uptime check: ON at ", vmToString(uptimeFeed), " with a ",
                vmToString(gracePeriod), "s grace period"
            ));
        }
        vmLog("next: fund the vault with the settlement token (script/Faucet.s.sol claims MockUSDG on testnet),");
        vmLog("      then verify feeds on the explorer");
    }

    function _registerAssets(AssetRegistry registry) internal {
        for (uint256 i = 0; i < SYMBOLS.length; i++) {
            string memory symbol = SYMBOLS[i];
            address token = vmEnvAddressOpt(string.concat("TOKEN_", symbol));
            address feed = vmEnvAddressOpt(string.concat("FEED_", symbol));
            if (token == address(0) || feed == address(0)) {
                vmLog(string.concat("skip ", symbol, " (set TOKEN_", symbol, " and FEED_", symbol, " to register)"));
                continue;
            }
            // A feed that reports something other than 8 decimals is rejected by the
            // registry; failing with the precision in the message beats a silent mispricing.
            require(feed.code.length > 0, "feed has no code at this address");
            uint8 feedDecimals = IAggregatorV3(feed).decimals();
            require(feedDecimals == ProtectionMath.PRICE_DECIMALS, "feed decimals must be 8");
            // Staleness 0 -> registry default (72h), per spec §2.
            registry.registerAsset(token, symbol, IAggregatorV3(feed), 0);
            vmLog(string.concat("registered ", symbol, " at ", vmToString(token), " (feed 8 decimals)"));
        }
    }
}
