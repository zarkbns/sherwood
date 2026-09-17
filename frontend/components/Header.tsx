"use client";

import { useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAccount, useDisconnect, useChainId, useSwitchChain } from "wagmi";
import { robinhoodTestnet } from "@/lib/chain";
import { IconShield, IconGauge, IconFile, IconVault, IconArrow } from "@/components/ui";
import { ConnectModal } from "@/components/ConnectModal";

const links = [
  { href: "/", label: "Dashboard", Icon: IconGauge },
  { href: "/protect", label: "Protect", Icon: IconShield },
  { href: "/notes", label: "Notes", Icon: IconFile },
  { href: "/vault", label: "Vault", Icon: IconVault },
];

const CHAIN_NAMES: Record<number, string> = {
  [robinhoodTestnet.id]: "Robinhood Chain Testnet",
};

function ConnectButton({ onConnect }: { onConnect: () => void }) {
  const { address, isConnected } = useAccount();
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
            className="rounded-full border border-action px-4 py-2 text-xs text-action transition-colors hover:bg-action/10"
          >
            Switch network
          </button>
        ) : (
          <span className="hidden text-xs text-mist lg:inline">{CHAIN_NAMES[chainId]}</span>
        )}
        <button
          onClick={() => disconnect()}
          title="Disconnect wallet"
          className="tnum rounded-full border border-line px-4 py-2 text-xs text-fog transition-colors hover:border-mist hover:text-ink"
        >
          {address.slice(0, 6)}…{address.slice(-4)}
        </button>
      </div>
    );
  }

  return (
    <button
      onClick={onConnect}
      className="btn-action inline-flex items-center gap-2 rounded-full px-5 py-2.5 text-sm"
    >
      Connect wallet
      <IconArrow className="h-4 w-4" />
    </button>
  );
}

export function Header() {
  const pathname = usePathname();
  const [connectOpen, setConnectOpen] = useState(false);
  return (
    <>
      <header className="sticky top-0 z-20 border-b border-line/60 bg-canvas/85 backdrop-blur-xl">
        <div className="mx-auto flex max-w-5xl items-center justify-between gap-4 px-5 py-3.5 sm:px-6">
          <Link href="/" className="flex items-center gap-2.5">
            <Image
              src="/logo.png"
              alt="Sherwood"
              width={64}
              height={64}
              priority
              className="h-8 w-8 rounded-xl object-contain"
            />
            <span className="font-display text-lg font-bold tracking-tight">
              Sherwood<span className="text-action">.</span>
            </span>
          </Link>

          <nav className="hidden items-center gap-1 sm:flex" aria-label="Primary">
            {links.map((l) => (
              <Link
                key={l.href}
                href={l.href}
                className={`rounded-full px-4 py-2 text-sm transition-colors duration-150 ${
                  pathname === l.href ? "bg-surface-2 text-ink" : "text-fog hover:bg-white/[0.04] hover:text-ink"
                }`}
              >
                {l.label}
              </Link>
            ))}
          </nav>

          <ConnectButton onConnect={() => setConnectOpen(true)} />
        </div>
      </header>

      <ConnectModal open={connectOpen} onClose={() => setConnectOpen(false)} />

      {/* Mobile tab bar — peers, not a drawer. Fixed, blurred, safe-area aware. */}
      <nav
        aria-label="Primary"
        className="fixed inset-x-0 bottom-0 z-20 border-t border-line/60 bg-canvas/90 pb-[max(env(safe-area-inset-bottom),12px)] pt-2 backdrop-blur-xl sm:hidden"
      >
        <div className="mx-auto flex max-w-md items-stretch justify-around px-4">
          {links.map((l) => {
            const active = pathname === l.href;
            return (
              <Link
                key={l.href}
                href={l.href}
                className={`flex min-h-[44px] flex-1 flex-col items-center gap-1 py-1 transition-colors ${
                  active ? "text-ink" : "text-mist"
                }`}
              >
                <l.Icon className={`h-5 w-5 ${active ? "text-action" : ""}`} />
                <span className="text-[10px] tracking-wide">{l.label}</span>
                <span className={`h-0.5 w-4 rounded-full ${active ? "bg-action" : "bg-transparent"}`} />
              </Link>
            );
          })}
        </div>
      </nav>
    </>
  );
}
