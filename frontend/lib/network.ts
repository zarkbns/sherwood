import { robinhoodTestnet } from "@/lib/chain";

/**
 * Network facts for the UI, derived from the chain definition that wagmi actually uses so
 * there is one source of truth. The point of surfacing these is the mistake this list
 * exists to prevent: a user funding gas on mainnet and wondering why the testnet app never
 * sees it. Both chains are Robinhood Chain and both are real, and the only difference the
 * user can act on is the chain ID and the RPC.
 */
export const NETWORK = {
  name: robinhoodTestnet.name,
  chainId: robinhoodTestnet.id,
  rpcUrl: robinhoodTestnet.rpcUrls.default.http[0],
  explorer: robinhoodTestnet.blockExplorers?.default.url ?? "",
  docs: "https://docs.robinhood.com/chain/connecting",
  /** The faucet host Robinhood's docs point at. See `faucetStatus` for why it is not a CTA. */
  faucet: "https://testnet.robinhoodchain.com",
  mainnet: { name: "Robinhood Chain", chainId: 4663, rpcUrl: "https://rpc.mainnet.chain.robinhood.com" },
} as const;

/**
 * Verified 2026-09-17: the host resolves (76.223.54.146) but nothing answers on https —
 * curl returns 000, twice, with and without a browser user agent — while
 * docs.robinhood.com/chain renders 200. So the documented faucet is not reachable from here
 * and must not be presented as a working source of testnet gas. The docs page is linked
 * instead, and the treasury fallback is offered because we control it.
 */
export const FAUCET_REACHABLE = false;

export const MAINNET_WARNING =
  "This is a testnet. Gas is testnet ETH, and mainnet ETH is not the same balance — funding chain 4663 will not pay for anything here.";
