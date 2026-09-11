"use client";

import { WagmiProvider, createConfig, http } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { injected, walletConnect } from "wagmi/connectors";
import { robinhoodTestnet } from "@/lib/chain";

const wcProjectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID;

const config = createConfig({
  chains: [robinhoodTestnet],
  connectors: [
    injected({ shimDisconnect: true }),
    // WalletConnect (mobile wallets) only when a real project id is configured.
    ...(wcProjectId
      ? [
          walletConnect({
            projectId: wcProjectId,
            metadata: {
              name: "SherwoodNotes",
              description: "Programmable downside protection for tokenized stocks",
              url: "https://sherwood.finance",
              icons: [],
            },
            showQrModal: true,
          }),
        ]
      : []),
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
