"use client";

import { useAccount, useBalance } from "wagmi";
import { formatUnits } from "viem";
import { Header } from "@/components/Header";
import { StatCard, Empty } from "@/components/ui";
import { useDeployed, useAssets, useNotes, useVaultStats, settlementTokenFor } from "@/lib/protocol";
import { fmtPrice, fmtUsd18, fmtExpiry, isExpired } from "@/lib/format";

export default function Dashboard() {
  const { address, isConnected } = useAccount();
  const { deployed, chainId } = useDeployed();
  const { assets } = useAssets();
  const { notes } = useNotes();
  const vault = useVaultStats();
  const st = settlementTokenFor(chainId);

  const { data: stBalance } = useBalance({
    address,
    token: st?.address,
    query: { enabled: !!address && !!st?.address },
  });

  const mine = notes.filter((n) => address && n.owner.toLowerCase() === address.toLowerCase());
  const active = mine.filter((n) => n.status === 0);
  const totalProtected = active.reduce((sum, n) => sum + n.protectedUSD18, 0n);

  return (
    <>
      <Header />
      <main className="mx-auto max-w-5xl px-6 py-10">
        {!deployed ? (
          <Empty
            title="Not deployed on this network"
            body="Sherwood is live on Robinhood Chain testnet only. Switch networks to continue — addresses are set at deploy time."
          />
        ) : (
          <>
            <h1 className="font-display text-4xl font-bold tracking-tight">
              Your position<span className="text-action">.</span>
            </h1>
            <p className="mt-2 text-sm text-mist">Keep the upside. Define the downside.</p>

            <div className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-3">
              <StatCard label="Active protection" value={fmtUsd18(totalProtected)} sub={`${active.length} active note${active.length === 1 ? "" : "s"}`} />
              <StatCard
                label="Stock held"
                value={assets
                  .filter((a) => a.balance && a.balance > 0n)
                  .map((a) => `${Number(formatUnits(a.balance!, a.decimals))} ${a.symbol}`)
                  .join(" · ") || "—"}
                sub="tokenized equities"
              />
              <StatCard
                label={st ? `${st.symbol} balance` : "Settlement token"}
                value={stBalance ? Number(formatUnits(stBalance.value, stBalance.decimals)).toFixed(2) : "—"}
                sub="available for premiums"
              />
            </div>

            <h2 className="mt-12 font-display text-xl font-bold">Your notes</h2>
            <div className="mt-4 space-y-3">
              {mine.length === 0 ? (
                <Empty
                  title="No protection yet"
                  body="Buy your first Protection Note: pick an asset, a floor, and a duration. All upside stays yours."
                />
              ) : (
                mine.map((n) => {
                  const asset = assets.find((a) => a.token === n.asset);
                  return (
                    <div key={n.id.toString()} className="inset-card flex flex-wrap items-center justify-between gap-4 rounded-3xl p-5">
                      <div>
                        <div className="font-display font-bold">
                          {asset?.symbol ?? "asset"} · {Number(n.level) / 1e16}% floor
                        </div>
                        <div className="mt-1 text-xs text-mist">
                          entry {fmtPrice(n.entryPrice)} · expires {fmtExpiry(n.expiry)}
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="font-display">{fmtUsd18(n.protectedUSD18)} protected</div>
                        <div className={`mt-1 text-xs ${n.status === 1 ? "text-mist" : isExpired(n.expiry) ? "text-action" : "text-fog"}`}>
                          {n.status === 1 ? "settled" : isExpired(n.expiry) ? "ready to settle" : "active"}
                        </div>
                      </div>
                    </div>
                  );
                })
              )}
            </div>

            <div className="mt-12 grid grid-cols-1 gap-4 sm:grid-cols-3">
              <StatCard label="Vault deposits" value={fmtTokenUnits(vault.totalDeposits, st?.decimals ?? 6, st?.symbol)} />
              <StatCard label="Reserved" value={fmtTokenUnits(vault.reserved, st?.decimals ?? 6, st?.symbol)} sub="collateral backing active notes" />
              <StatCard label="Capacity" value={fmtTokenUnits(vault.availableCapacity, st?.decimals ?? 6, st?.symbol)} sub="available for new protection" />
            </div>
          </>
        )}
      </main>
    </>
  );
}

function fmtTokenUnits(value: bigint | undefined, decimals: number, symbol?: string): string {
  if (value === undefined) return "—";
  const num = Number(formatUnits(value, decimals)).toLocaleString("en-US", { maximumFractionDigits: 2 });
  return symbol ? `${num} ${symbol}` : num;
}
