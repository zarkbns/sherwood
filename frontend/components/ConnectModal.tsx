"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useAccount, useConnect } from "wagmi";
import { IconAlert, IconCheck, IconShield, IconWallet } from "@/components/ui";
import { injectedWallet } from "@/lib/wallets";

/**
 * The connect surface. Nothing in here connects on the visitor's behalf: the session starts
 * disconnected (see Providers on why shimDisconnect is off) and a wallet only becomes active
 * when its row is clicked. A row click can still resolve without a wallet popup when the
 * extension has already granted this site permission — that grant lives in the wallet, not
 * in the dapp, and no dapp code can force the approval dialog back up. Revoking it happens
 * inside the wallet.
 */

type Row = {
  key: string;
  name: string;
  blurb: string;
  index: number;
};

export function ConnectModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { connect, connectors, isPending, error, reset } = useConnect();
  const { isConnected } = useAccount();
  const panelRef = useRef<HTMLDivElement>(null);
  // Which row was clicked. This useConnect exposes no pending-connector id (checked), so
  // the busy state is tracked locally — otherwise isPending would light every row at once.
  const [pendingKey, setPendingKey] = useState<string | null>(null);

  const rows = useMemo<Row[]>(() => {
    const detected = injectedWallet();
    const list: Row[] = [];
    connectors.forEach((connector, index) => {
      const type = connector.type;
      if (type === "injected") {
        // The detected wallet names the row; a browser with no wallet at all is still
        // offered, because MetaMask-style onboarding is the honest fallback.
        list.push({
          key: "injected",
          name: detected?.id === "injected" || !detected ? "Browser wallet" : detected.name,
          blurb: detected?.blurb ?? "No wallet detected — install one, then retry",
          index,
        });
        return;
      }
      if (detected && ((detected.id === "metamask" && type === "metaMask") || (detected.id === "coinbase" && type === "coinbaseWallet"))) {
        // Already offered as the detected injected wallet; don't list it twice.
        return;
      }
      if (type === "metaMask") list.push({ key: "metamask", name: "MetaMask", blurb: "Extension or mobile", index });
      else if (type === "coinbaseWallet") list.push({ key: "coinbase", name: "Coinbase Wallet", blurb: "Extension or mobile", index });
      else if (type === "walletConnect") list.push({ key: "walletconnect", name: "WalletConnect", blurb: "Scan with a mobile wallet", index });
      else list.push({ key: type, name: connector.name, blurb: "Continue in the wallet app", index });
    });
    return list;
  }, [connectors]);

  useEffect(() => {
    if (isConnected) onClose();
  }, [isConnected, onClose]);

  useEffect(() => {
    if (!open) {
      reset();
      setPendingKey(null);
      return;
    }
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    panelRef.current?.focus();
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose, reset]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center px-4 py-6"
      role="dialog"
      aria-modal="true"
      aria-labelledby="connect-title"
    >
      <button
        type="button"
        aria-label="Close"
        onClick={onClose}
        className="absolute inset-0 cursor-default bg-black/70 backdrop-blur-sm"
      />

      <div
        ref={panelRef}
        tabIndex={-1}
        className="inset-card rise relative w-full max-w-[380px] rounded-3xl border-line/80 p-8 outline-none"
      >
        <div className="flex flex-col items-center">
          <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-surface-2 text-action">
            <IconShield className="h-6 w-6" />
          </span>
          <h2 id="connect-title" className="mt-4 text-xl font-semibold tracking-tight text-ink">
            Connect a wallet
          </h2>
          <p className="mt-1 text-center text-xs leading-relaxed text-mist">
            Protection is bought and settled on-chain. Pick a wallet to continue — Sherwood
            never moves funds without your signature.
          </p>
        </div>

        <div className="mt-6 flex flex-col gap-2">
          {rows.map((row) => {
            const busy = isPending && pendingKey === row.key;
            return (
              <button
                key={row.key}
                type="button"
                disabled={isPending}
                onClick={() => {
                  setPendingKey(row.key);
                  connect({ connector: connectors[row.index] });
                }}
                className="flex min-h-[44px] w-full items-center gap-3 rounded-xl border border-line bg-surface-2 px-4 text-left transition-colors duration-150 hover:border-action focus-visible:border-action disabled:opacity-50"
              >
                <span className="text-mist">
                  {busy ? <IconCheck className="h-5 w-5 text-action" /> : <IconWallet className="h-5 w-5" />}
                </span>
                <span className="flex-1">
                  <span className="block text-sm text-ink">{row.name}</span>
                  <span className="block text-[11px] text-mist">{row.blurb}</span>
                </span>
                {busy ? <span className="text-[11px] text-action">Opening…</span> : null}
              </button>
            );
          })}
        </div>

        {error ? (
          <p className="mt-4 flex items-start gap-2 text-xs text-loss">
            <IconAlert className="mt-px h-4 w-4 shrink-0" />
            <span>{error.message || "The wallet rejected or cancelled the request."}</span>
          </p>
        ) : null}

        <p className="mt-6 text-center text-[11px] leading-relaxed text-mist">
          Testnet only. Nothing here is a real position, a real price, or a real payout.
        </p>
      </div>
    </div>
  );
}
