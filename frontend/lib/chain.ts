import { defineChain } from "viem";

/**
 * Robinhood Chain testnet. Verified values from docs.robinhood.com/chain/connecting:
 * chain ID 46630, public RPC is rate-limited (use NEXT_PUBLIC_RPC_ROBINHOOD_TESTNET
 * with an Alchemy endpoint in production), explorer at explorer.testnet.chain.robinhood.com.
 *
 * The documented RPC path ends in /rpc; both forms answer, and this uses the documented
 * one so what the network card prints is exactly what the app connects to. Checked
 * 2026-09-17: eth_chainId, eth_getCode, eth_getLogs and eth_call all work on it.
 */
export const robinhoodTestnet = defineChain({
  id: 46630,
  name: "Robinhood Chain Testnet",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: {
      http: [process.env.NEXT_PUBLIC_RPC_ROBINHOOD_TESTNET ?? "https://rpc.testnet.chain.robinhood.com/rpc"],
    },
  },
  blockExplorers: {
    default: { name: "Robinhood Chain Explorer", url: "https://explorer.testnet.chain.robinhood.com" },
  },
  testnet: true,
});
