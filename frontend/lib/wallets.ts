"use client";

/**
 * Wallet detection for the connect surface.
 *
 * There is no `okxWallet` connector in the pinned wagmi (2.16.9) — verified: it is not
 * exported and the installed package contains no `okx` or EIP-6963 references at all. OKX
 * Wallet therefore connects through the standard EIP-1193 `injected` connector; what we can
 * do is recognise it and say so, instead of showing a faceless "Injected" row. Detection
 * reads the flags those wallets publish on the provider, so it must never run at module
 * scope — this app renders on the server too (`ssr: true`).
 */

export type DetectedWallet = {
  id: string;
  name: string;
  blurb: string;
};

type ProviderWithFlags = {
  isOkxWallet?: boolean;
  okxWallet?: unknown;
  isMetaMask?: boolean;
  coinbaseWalletExtension?: unknown;
};

declare global {
  interface Window {
    ethereum?: ProviderWithFlags;
    okxWallet?: ProviderWithFlags;
  }
}

/**
 * The wallet the `injected` connector will actually reach, best-labelled. Order matters:
 * OKX sets its own flag alongside a generic provider, so check it before MetaMask, whose
 * `isMetaMask` some other wallets also set.
 */
export function injectedWallet(): DetectedWallet | null {
  if (typeof window === "undefined") return null;
  const provider = window.ethereum as ProviderWithFlags | undefined;
  if (!provider && !window.okxWallet) return null;

  const flags: ProviderWithFlags = provider ?? {};
  if (flags.isOkxWallet || window.okxWallet) {
    return { id: "okx", name: "OKX Wallet", blurb: "DEX extension or in-app browser" };
  }
  if (flags.coinbaseWalletExtension) {
    return { id: "coinbase", name: "Coinbase Wallet", blurb: "Browser extension detected" };
  }
  if (flags.isMetaMask) {
    return { id: "metamask", name: "MetaMask", blurb: "Browser extension detected" };
  }
  return { id: "injected", name: "Browser wallet", blurb: "Whatever wallet is installed" };
}
