"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from "wagmi";
import { robinhoodTestnet } from "@/lib/chain";

const links = [
  { href: "/", label: "Dashboard" },
  { href: "/protect", label: "Protect" },
  { href: "/notes", label: "Notes" },
  { href: "/vault", label: "Vault" },
];

const CHAIN_NAMES: Record<number, string> = {
  [robinhoodTestnet.id]: "Robinhood Chain Testnet",
};

function ConnectButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();

  if (isConnected && address) {
    const onSupported = chainId === robinhoodTestnet.id;
    return (
      <div className="flex items-center gap-2">
        {!onSupported ? (
          <button
            onClick={() => switchChain({ chainId: robinhoodTestnet.id })}
            className="rounded-xl border border-action px-3 py-2 text-xs text-action"
          >
            Switch network
          </button>
        ) : (
          <span className="hidden text-xs text-mist sm:inline">{CHAIN_NAMES[chainId]}</span>
        )}
        <span className="rounded-xl border border-line px-3 py-2 text-xs text-fog">
          {address.slice(0, 6)}…{address.slice(-4)}
        </span>
        <button onClick={() => disconnect()} className="text-xs text-mist hover:text-ink">
          Exit
        </button>
      </div>
    );
  }

  const injectedConnector = connectors.find((c) => c.type === "injected") ?? connectors[0];
  return (
    <button
      onClick={() => injectedConnector && connect({ connector: injectedConnector })}
      disabled={isPending || !injectedConnector}
      className="btn-action rounded-xl px-4 py-2 text-sm"
    >
      {isPending ? "Connecting…" : "Connect wallet"}
    </button>
  );
}

export function Header() {
  const pathname = usePathname();
  return (
    <header className="sticky top-0 z-10 border-b border-line bg-canvas/90 backdrop-blur">
      <div className="mx-auto flex max-w-5xl items-center justify-between gap-4 px-6 py-4">
        <Link href="/" className="font-display text-lg font-bold tracking-tight">
          Sherwood<span className="text-action">.</span>
        </Link>
        <nav className="hidden gap-6 text-sm text-fog sm:flex">
          {links.map((l) => (
            <Link key={l.href} href={l.href} className={pathname === l.href ? "text-ink" : "hover:text-ink"}>
              {l.label}
            </Link>
          ))}
        </nav>
        <ConnectButton />
      </div>
    </header>
  );
}
