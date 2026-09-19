"use client";

/**
 * EIP-1193 provider types. Connect is one button into WalletConnect's own chooser (see
 * lib/connect), so there is no injected-wallet detection left here — but the add-network
 * call still talks to an injected provider directly, which is what these types describe.
 * The augmentation must never run at module scope against `window`: this app renders on
 * the server too (`ssr: true`).
 */

type ProviderWithFlags = Eip1193Provider & {
  isOkxWallet?: boolean;
  okxWallet?: unknown;
  isMetaMask?: boolean;
  coinbaseWalletExtension?: unknown;
};

/** The EIP-1193 surface every provider above speaks, whether injected or in-app. */
export type Eip1193Provider = {
  request(args: { method: string; params?: unknown[] }): Promise<unknown>;
};

declare global {
  interface Window {
    ethereum?: ProviderWithFlags;
    okxWallet?: ProviderWithFlags;
  }
}
