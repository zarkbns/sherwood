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
  // Robinhood Chain testnet (46630) — v6 deployed 2026-09-16, see deploy/deployments.json.
  // Env overrides win, so a redeployment can be pointed at without a code change.
  // v6 carries the six audit fixes (aggregate exposure cap, 30-day claim window with
  // forfeit, per-note settlement feed binding, set-once note-contract binding, 18-dec
  // token validation) on top of v5's eligibleAmount basis; the v5 stack (0x4DE45eCb…/
  // 0x663da2d1…/0x1dd47dE1…/0x073AEBD5…) stays on-chain holding the v5 demo evidence
  // but is no longer the default.
  46630: {
    registry: (process.env.NEXT_PUBLIC_REGISTRY_ROBINHOOD_TESTNET ?? "0xC3aCC52C3dAF1c2D1B65725781063dCfc6a1c6Fd") as Address,
    oracle: (process.env.NEXT_PUBLIC_ORACLE_ROBINHOOD_TESTNET ?? "0x8366fcabD007361D899A55A6dA3455531C070096") as Address,
    vault: (process.env.NEXT_PUBLIC_VAULT_ROBINHOOD_TESTNET ?? "0x8F7D2099738e72e40CfF2e6fF5918d11f516f988") as Address,
    note: (process.env.NEXT_PUBLIC_NOTE_ROBINHOOD_TESTNET ?? "0xb2F4391cf4c997C71bDC39d831DD389cECe06729") as Address,
  },
};

export function addressesFor(chainId: number): ProtocolAddresses | null {
  const d = deployments[chainId];
  if (!d) return null;
  if (!d.registry || !d.oracle || !d.vault || !d.note) return null;
  return d as ProtocolAddresses;
}

/**
 * The settlement token every premium, vault reserve and payout moves in.
 * - mainnet (4663): USDG (Paxos Global Dollar) 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168,
 *   per docs.robinhood.com/chain/contracts.
 * - testnet (46630): MockUSDG 0x8c4aa106a0A0d9ECAeD5C87e1AE766aa8Efbf006 — a source-verified
 *   test token whose public faucet pays 1,000 per address per 24h. Chosen because Robinhood's
 *   testnet USDG drip (0x7E955252E15c84f5768B83c41a71F9eba181802F, the canonical real token,
 *   verified in README "Verified Environment Facts") has never funded a protocol wallet, so
 *   nothing could be paid. Its on-chain symbol() is "USDG" and decimals() is 6, identical in
 *   shape to USDG, so the labels below stay truthful to the contract the app is talking to.
 *   Switching testnet to real USDG is this one address (or NEXT_PUBLIC_USDG_ROBINHOOD_TESTNET)
 *   plus a vault redeploy — SherwoodVault binds its token as immutable.
 * Contracts read decimals() on-chain regardless; these values drive display only.
 */
export const SETTLEMENT_TOKEN: Record<number, { address: Address; symbol: string; decimals: number }> = {
  46630: { address: (process.env.NEXT_PUBLIC_USDG_ROBINHOOD_TESTNET ?? "0x8c4aa106a0A0d9ECAeD5C87e1AE766aa8Efbf006") as Address, symbol: "USDG", decimals: 6 },
};
