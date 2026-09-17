"use client";

import { WagmiProvider, createConfig, http } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { coinbaseWallet, injected, metaMask, walletConnect } from "wagmi/connectors";
import { robinhoodTestnet } from "@/lib/chain";

const wcProjectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID;

const metadata = {
  name: "SherwoodNotes",
  description: "Programmable downside protection for tokenized stocks",
  url: "https://sherwood.finance",
  icons: [],
};

const config = createConfig({
  chains: [robinhoodTestnet],
  // shimDisconnect is deliberately off. It exists to fake a disconnectable session for
  // wallets that never implemented EIP-1193 disconnect, and the price is that the session
  // gets persisted and silently restored on the next load — which is why connecting looked
  // automatic and never asked anyone to approve anything. Without it every session starts
  // disconnected, and connecting is a deliberate act through the modal.
  //
  // OKX Wallet has no dedicated connector in the pinned wagmi (2.16.9 exports no
  // `okxWallet`), so it arrives through `injected` and is named at runtime in the modal.
  connectors: [
    injected(),
    metaMask(),
    coinbaseWallet({ ...metadata, preference: "all" }),
    // WalletConnect (mobile wallets) only when a real project id is configured.
    ...(wcProjectId ? [walletConnect({ projectId: wcProjectId, metadata, showQrModal: true })] : []),
  ],
  transports: {
    [robinhoodTestnet.id]: http(process.env.NEXT_PUBLIC_RPC_ROBINHOOD_TESTNET),
  },
  ssr: true,
});

const queryClient = new QueryClient();

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}
