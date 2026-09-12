import { Address } from "viem";

/**
 * Deployed protocol addresses for Robinhood Chain testnet (46630). Populated from
 * `script/Deploy.s.sol` output at deploy time; set via NEXT_PUBLIC_* env or here.
 * A missing address means the protocol is not deployed yet and the UI disables it.
 */
export type ProtocolAddresses = {
  registry: Address;
  oracle: Address;
  vault: Address;
  note: Address;
};

const deployments: Partial<Record<number, ProtocolAddresses>> = {
  // Robinhood Chain testnet (46630) — deployed 2026-09-12, see deploy/deployments.json.
  // Env overrides win, so a redeployment can be pointed at without a code change.
  46630: {
    registry: (process.env.NEXT_PUBLIC_REGISTRY_ROBINHOOD_TESTNET ?? "0x41e7bc706D7aBF76Dbe72d50240F9f6AF151088d") as Address,
    oracle: (process.env.NEXT_PUBLIC_ORACLE_ROBINHOOD_TESTNET ?? "0x2B079894ADab3e806B37A6a0Bd0F33338CDbCED9") as Address,
    vault: (process.env.NEXT_PUBLIC_VAULT_ROBINHOOD_TESTNET ?? "0x491ccb7F76632b7812D2A8d0d48Eec0292c41c70") as Address,
    note: (process.env.NEXT_PUBLIC_NOTE_ROBINHOOD_TESTNET ?? "0x9FE9bb09cA3777AaffC7C20084c10CB1C2D419E0") as Address,
  },
};

export function addressesFor(chainId: number): ProtocolAddresses | null {
  const d = deployments[chainId];
  if (!d) return null;
  if (!d.registry || !d.oracle || !d.vault || !d.note) return null;
  return d as ProtocolAddresses;
}

/**
 * USDG (Paxos Global Dollar) settles every premium and payout. Verified addresses:
 * mainnet 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168 (docs.robinhood.com/chain/contracts),
 * testnet 0x7E955252E15c84f5768B83c41a71F9eba181802F (README "Verified Environment Facts").
 * Decimals are 6 on both chains (read via cast); contracts read decimals() on-chain regardless.
 */
export const SETTLEMENT_TOKEN: Record<number, { address: Address; symbol: string; decimals: number }> = {
  46630: { address: (process.env.NEXT_PUBLIC_USDG_ROBINHOOD_TESTNET ?? "0x7E955252E15c84f5768B83c41a71F9eba181802F") as Address, symbol: "USDG", decimals: 6 },
};
