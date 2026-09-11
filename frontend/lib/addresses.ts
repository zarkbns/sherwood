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
  // Robinhood Chain testnet (46630)
  46630: {
    registry: (process.env.NEXT_PUBLIC_REGISTRY_ROBINHOOD_TESTNET ?? "") as Address,
    oracle: (process.env.NEXT_PUBLIC_ORACLE_ROBINHOOD_TESTNET ?? "") as Address,
    vault: (process.env.NEXT_PUBLIC_VAULT_ROBINHOOD_TESTNET ?? "") as Address,
    note: (process.env.NEXT_PUBLIC_NOTE_ROBINHOOD_TESTNET ?? "") as Address,
  },
};

export function addressesFor(chainId: number): ProtocolAddresses | null {
  const d = deployments[chainId];
  if (!d) return null;
  if (!d.registry || !d.oracle || !d.vault || !d.note) return null;
  return d as ProtocolAddresses;
}

/**
 * USDG (Paxos Global Dollar) settles every premium and payout. On Robinhood Chain
 * mainnet the canonical address is 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168
 * (docs.robinhood.com/chain/contracts). The testnet address is not published yet —
 * set it via NEXT_PUBLIC_USDG_ROBINHOOD_TESTNET once verified on the testnet explorer.
 * Decimals are the Paxos-standard 18; contracts read decimals() on-chain regardless.
 */
export const SETTLEMENT_TOKEN: Record<number, { address: Address; symbol: string; decimals: number }> = {
  46630: { address: (process.env.NEXT_PUBLIC_USDG_ROBINHOOD_TESTNET ?? "") as Address, symbol: "USDG", decimals: 18 },
};
