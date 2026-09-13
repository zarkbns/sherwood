// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployConfig} from "./Config.s.sol";
import {ScriptBase} from "./ScriptBase.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @title Faucet
/// @notice TESTNET ONLY. Claims the settlement token so the protocol's money paths can
///         actually be exercised: vault reserves, buyer premiums and payouts all move
///         this token. The Robinhood testnet USDG drip never reached protocol wallets,
///         so the demo stack settles against MockUSDG, whose public `faucet()` hands out
///         1,000 tokens per address per 24h (verified live on 46630, 2026-09-13).
///
///         Refuses to run on mainnet — canonical USDG has no public mint and the mock's
///         admin can mint unlimited balance, so a mainnet claim is meaningless by
///         definition.
///
///         Required env: PRIVATE_KEY (the claiming wallet)
///         Optional env: SETTLEMENT_TOKEN (defaults to the chain's configured token)
///
///         Run: forge script script/Faucet.s.sol --rpc-url <RPC_URL> --broadcast
contract Faucet is ScriptBase {
    function run() external {
        DeployConfig config = new DeployConfig();
        uint256 chainId = block.chainid;
        require(chainId != config.ROBINHOOD_MAINNET_CHAIN_ID(), "faucet is testnet-only");

        address settlement = config.resolveSettlementToken(chainId, vmEnvAddressOpt("SETTLEMENT_TOKEN"));
        require(settlement != address(0), "no settlement token for this chain: export SETTLEMENT_TOKEN");
        require(settlement.code.length > 0, "settlement token has no code at this address");

        uint256 privateKey = vmEnvUint("PRIVATE_KEY", 0);
        require(privateKey != 0, "PRIVATE_KEY is required to sign the claim");
        address claimer = vmAddr(privateKey);

        IFaucetToken token = IFaucetToken(settlement);
        uint256 amount = token.FAUCET_AMOUNT();
        uint256 remaining = token.faucetCooldownRemaining(claimer);

        vmLog(string.concat("token: ", vmToString(settlement)));
        vmLog(string.concat("claimer: ", vmToString(claimer)));
        vmLog(string.concat("per claim: ", vmToString(amount), " (", vmToString(IERC20(settlement).decimals()),
            " decimals)"));

        if (remaining > 0) {
            vmLog(string.concat("in cooldown: ", vmToString(remaining), "s left, next claim at ",
                vmToString(block.timestamp + remaining)));
            vmLog(string.concat("balance: ", vmToString(IERC20(settlement).balanceOf(claimer))));
            return;
        }

        uint256 balanceBefore = IERC20(settlement).balanceOf(claimer);

        vmStartBroadcast();
        token.faucet();
        vmStopBroadcast();

        uint256 balanceAfter = IERC20(settlement).balanceOf(claimer);
        require(balanceAfter - balanceBefore == amount, "faucet did not mint the advertised amount");

        vmLog(string.concat("minted: ", vmToString(amount)));
        vmLog(string.concat("balance: ", vmToString(balanceBefore), " -> ", vmToString(balanceAfter)));
        vmLog(string.concat("next claim in: ", vmToString(token.faucetCooldownRemaining(claimer)), "s"));
        vmLog("next: approve the vault and deposit, or run script/DemoCreate.s.sol");
    }
}

/// @dev The faucet surface of the testnet settlement token, as verified on
///      explorer.testnet.chain.robinhood.com (src/mocks/MockUSDG.sol).
interface IFaucetToken {
    function faucet() external;
    function FAUCET_AMOUNT() external view returns (uint256);
    function faucetCooldownRemaining(address account) external view returns (uint256);
}
