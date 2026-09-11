// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployConfig} from "./Config.s.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {ProtectionOracle} from "../src/ProtectionOracle.sol";
import {SherwoodVault} from "../src/SherwoodVault.sol";
import {ProtectionNote} from "../src/ProtectionNote.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @title Deploy
/// @notice Full protocol deployment, chain-configured via DeployConfig (spec §7).
///         Sherwood targets Robinhood Chain: the settlement token is on-chain config
///         for mainnet (canonical USDG) and resolved from SETTLEMENT_TOKEN on the
///         testnet until its USDG address is verified and published.
///         Stock tokens and Chainlink feeds are read from the environment so feed
///         addresses can be verified per chain at deploy time instead of baked in.
///
///         Required when the chain has no configured token:
///           SETTLEMENT_TOKEN=0x...
///         Optional per-asset registration (repeatable pattern):
///           TOKEN_TSLA=0x... FEED_TSLA=0x...   (also AMZN, NFLX, PLTR, AMD)
///
///         Run: forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast --verify
contract Deploy {
    address constant VM_ADDRESS = address(uint160(uint256(uint160(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D))));

    string[] internal SYMBOLS = ["TSLA", "AMZN", "NFLX", "PLTR", "AMD"];

    function run() external {
        uint256 chainId = block.chainid;
        DeployConfig.ChainConfig memory cfg = new DeployConfig().get(chainId);

        address settlement = cfg.settlementToken != address(0) ? cfg.settlementToken : vmEnvAddress("SETTLEMENT_TOKEN");
        vmLog(string.concat("chain: ", vmToString(chainId)));
        vmLog(string.concat("settlement token: ", vmToString(settlement)));

        vmStartBroadcast();

        AssetRegistry registry = new AssetRegistry();
        ProtectionOracle oracle = new ProtectionOracle();
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

        vmLog("deployed:");
        vmLog(string.concat("  AssetRegistry:    ", vmToString(address(registry))));
        vmLog(string.concat("  ProtectionOracle: ", vmToString(address(oracle))));
        vmLog(string.concat("  SherwoodVault:    ", vmToString(address(vault))));
        vmLog(string.concat("  ProtectionNote:   ", vmToString(address(note))));
        vmLog("next: fund the vault with the settlement token, then verify feeds on the explorer");
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
            // Staleness 0 -> registry default (72h), per spec §2.
            registry.registerAsset(token, symbol, IAggregatorV3(feed), 0);
            vmLog(string.concat("registered ", symbol, " at ", vmToString(token)));
        }
    }

    // --- cheatcode shims: no forge-std, the build stays dependency-free ---

    function vmStartBroadcast() internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("startBroadcast()"));
        require(ok, "startBroadcast failed");
    }

    function vmStopBroadcast() internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("stopBroadcast()"));
        require(ok, "stopBroadcast failed");
    }

    function vmLog(string memory message) internal {
        (bool ok, ) = VM_ADDRESS.call(abi.encodeWithSignature("log(string)", message));
        ok;
    }

    function vmToString(uint256 value) internal returns (string memory) {
        (bool ok, bytes memory data) = VM_ADDRESS.call(abi.encodeWithSignature("toString(uint256)", value));
        require(ok, "toString failed");
        return abi.decode(data, (string));
    }

    function vmToString(address account) internal returns (string memory) {
        (bool ok, bytes memory data) = VM_ADDRESS.call(abi.encodeWithSignature("toString(address)", account));
        require(ok, "toString failed");
        return abi.decode(data, (string));
    }

    function vmEnvString(string memory key) internal returns (string memory) {
        (bool ok, bytes memory data) = VM_ADDRESS.call(abi.encodeWithSignature("envString(string)", key));
        require(ok, "envString failed");
        return abi.decode(data, (string));
    }

    function vmEnvOr(string memory key, string memory fallbackValue) internal returns (string memory) {
        (bool ok, bytes memory data) =
            VM_ADDRESS.call(abi.encodeWithSignature("envOr(string,string)", key, fallbackValue));
        require(ok, "envOr failed");
        return abi.decode(data, (string));
    }

    function vmParseAddress(string memory value) internal returns (address) {
        (bool ok, bytes memory data) = VM_ADDRESS.call(abi.encodeWithSignature("parseAddress(string)", value));
        require(ok, "parseAddress failed");
        return abi.decode(data, (address));
    }

    function vmEnvAddress(string memory key) internal returns (address) {
        return vmParseAddress(vmEnvString(key));
    }

    function vmEnvAddressOpt(string memory key) internal returns (address) {
        string memory value = vmEnvOr(key, "");
        if (bytes(value).length == 0) return address(0);
        return vmParseAddress(value);
    }
}
