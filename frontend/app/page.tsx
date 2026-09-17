"use client";

import { useAccount, useBalance } from "wagmi";
import { formatUnits } from "viem";
import Link from "next/link";
import { Header } from "@/components/Header";
import {
  StatCard,
  Skeleton,
  EmptyState,
  Pill,
  ProgressBar,
  Eyebrow,
  IconShield,
  IconFile,
  IconArrow,
} from "@/components/ui";
import { useDeployed, useAssets, useNotes, useVaultStats, settlementTokenFor } from "@/lib/protocol";
import { fmtUsd18, fmtUsd18Compact, fmtQty, fmtPrice, fmtCountdown, isExpired } from "@/lib/format";
import { TokenLogo } from "@/components/TokenLogo";

export default function Dashboard() {
  const { address, isConnected } = useAccount();
  const { deployed, chainId } = useDeployed();
  const { assets, isLoading: loadingAssets } = useAssets();
  const { notes, isLoading: loadingNotes } = useNotes();
  const vault = useVaultStats();
  const st = settlementTokenFor(chainId);

  const { data: stBalance } = useBalance({
    address,
    token: st?.address,
    query: { enabled: !!address && !!st?.address },
  });

  const held = assets.filter((a) => a.balance !== undefined && a.balance > 0n);
  // Everything the registry lists, holdings first. A zero balance is information, not
  // noise: filtering to funded positions only made a four-asset app look empty for a
  // wallet that simply had not been funded yet.
  const listed = [...assets].sort(
    (a, b) => Number((b.balance ?? 0n) > 0n) - Number((a.balance ?? 0n) > 0n)
  );
  const positionValue = held.reduce((sum, a) => sum + ((a.balance! * (a.price8 ?? 0n)) / 10n ** 8n), 0n);

  const mine = notes.filter((n) => address && n.owner.toLowerCase() === address.toLowerCase());
  const active = mine.filter((n) => n.status === 0);
  const totalProtected = active.reduce((sum, n) => sum + n.protectedUSD18, 0n);
  const premiumSpent = mine.reduce((sum, n) => sum + n.premiumUSD18, 0n);

  const utilization =
    vault.totalDeposits !== undefined && vault.reserved !== undefined && vault.totalDeposits > 0n
      ? Number(vault.reserved) / Number(vault.totalDeposits)
      : 0;
  const tok = (value: bigint | undefined) =>
    value === undefined
      ? "—"
      : `${Number(formatUnits(value, st?.decimals ?? 6)).toLocaleString("en-US", { maximumFractionDigits: 2 })} ${st?.symbol ?? ""}`.trim();

  return (
    <>
      <Header />
      <main className="mx-auto max-w-5xl px-5 pb-28 pt-8 sm:px-6 sm:pb-14 sm:pt-12">
        {!deployed ? (
          <EmptyState
            icon={<IconShield className="h-6 w-6" />}
            title="Not deployed on this network"
            body="Sherwood is live on Robinhood Chain testnet only. Switch networks to continue — addresses are set at deploy time."
          />
        ) : (
          <>
            {/* Hero — the number you came for. */}
            <section className="rise">
              <Eyebrow>Portfolio · Robinhood Chain testnet</Eyebrow>
              <div className="tnum mt-3 font-display text-5xl font-bold leading-none tracking-tight sm:text-6xl">
                {isConnected ? fmtUsd18Compact(positionValue) : "—"}
              </div>
              <p className="mt-3 text-sm text-mist">
                {isConnected
                  ? `${held.length} position${held.length === 1 ? "" : "s"} held · ${active.length} protection${active.length === 1 ? "" : "s"} active · upside stays yours`
                  : "Connect a wallet to see your positions and protection."}
              </p>
            </section>

            {/* Stats */}
            <section className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-3">
              <StatCard
                label="Protected floor"
                value={isConnected ? fmtUsd18Compact(totalProtected) : "—"}
                sub={`${active.length} active note${active.length === 1 ? "" : "s"}`}
                delay={60}
              />
              <StatCard
                label="Premium invested"
                value={isConnected ? fmtUsd18Compact(premiumSpent) : "—"}
                sub="all notes, spent or active"
                delay={120}
              />
              <StatCard
                label={`${st?.symbol ?? "Settlement"} balance`}
                value={stBalance ? fmtCompactToken(stBalance.value, stBalance.decimals) : "—"}
                sub="available for premiums"
                delay={180}
              />
            </section>

            {/* Holdings */}
            <section className="mt-12">
              <div className="flex items-baseline justify-between">
                <Eyebrow>Your holdings</Eyebrow>
                <Link href="/protect" className="inline-flex items-center gap-1 text-xs text-action hover:underline">
                  Protect a position <IconArrow className="h-3.5 w-3.5" />
                </Link>
              </div>
              <div className="mt-3 space-y-2">
                {loadingAssets ? (
                  <>
                    <SkeletonRow />
                    <SkeletonRow />
                  </>
                ) : listed.length === 0 ? (
                  <EmptyState
                    icon={<IconShield className="h-6 w-6" />}
                    title="Nothing registered on this network"
                    body="Sherwood covers whatever the asset registry lists. No assets are registered on this chain yet."
                    actionHref="/protect"
                    actionLabel="See what Sherwood covers"
                  />
                ) : (
                  listed.map((a, i) => {
                    const hasBalance = a.balance !== undefined && a.balance > 0n;
                    return (
                      <div
                        key={a.token}
                        className="inset-card inset-card--press rise flex items-center justify-between gap-4 rounded-2xl px-4 py-3.5"
                        style={{ animationDelay: `${i * 50}ms` }}
                      >
                        <div className="flex min-w-0 items-center gap-3">
                          <TokenLogo symbol={a.symbol} />
                          <span className="min-w-0">
                            <span className="block truncate text-sm text-ink">{a.name ?? a.symbol}</span>
                            <span className="tnum block text-xs text-mist">
                              {a.name ? `${a.symbol} · ` : ""}
                              {a.balance === undefined
                                ? "Connect to see balance"
                                : `${fmtQty(a.balance, a.decimals)} held`}
                            </span>
                          </span>
                        </div>
                        <div className="text-right">
                          <div className={`tnum text-sm ${hasBalance ? "text-ink" : "text-mist"}`}>
                            {hasBalance && a.price8 !== undefined
                              ? fmtUsd18((a.balance! * a.price8) / 10n ** 8n)
                              : "—"}
                          </div>
                          <div className="tnum text-xs text-mist">{fmtPrice(a.price8)}</div>
                        </div>
                      </div>
                    );
                  })
                )}
              </div>
            </section>

            {/* Active protection */}
            <section className="mt-12">
              <div className="flex items-baseline justify-between">
                <Eyebrow>Active protection</Eyebrow>
                <Link href="/notes" className="inline-flex items-center gap-1 text-xs text-action hover:underline">
                  All notes <IconArrow className="h-3.5 w-3.5" />
                </Link>
              </div>
              <div className="mt-3 space-y-2">
                {loadingNotes ? (
                  <SkeletonRow />
                ) : active.length === 0 ? (
                  <EmptyState
                    icon={<IconFile className="h-6 w-6" />}
                    title="Nothing protected yet"
                    body="Buy a Protection Note: define a floor on a position you hold, keep every dollar of upside. The quote is priced live by the contract."
                    actionHref="/protect"
                    actionLabel="Buy protection"
                  />
                ) : (
                  active.map((n, i) => {
                    const asset = assets.find((a) => a.token === n.asset);
                    const expired = isExpired(n.expiry);
                    return (
                      <div
                        key={n.id.toString()}
                        className="inset-card rise rounded-2xl px-4 py-4"
                        style={{ animationDelay: `${i * 50}ms` }}
                      >
                        <div className="flex items-center justify-between gap-4">
                          <div className="min-w-0">
                            <div className="truncate text-sm text-ink">
                              <span className="font-display font-bold">{asset?.symbol ?? "asset"}</span>
                              <span className="text-mist"> · </span>
                              <span className="tnum">{Number(n.level) / 1e16}% floor</span>
                            </div>
                            <div className="tnum mt-1 text-xs text-mist">
                              {fmtQty(n.amount, asset?.decimals ?? 18)} · entry {fmtPrice(n.entryPrice)} ·{" "}
                              {expired ? "matured" : fmtCountdown(n.expiry)}
                            </div>
                          </div>
                          <div className="shrink-0 text-right">
                            <div className="tnum text-sm text-ink">{fmtUsd18Compact(n.protectedUSD18)}</div>
                            <div className="mt-1.5">
                              <Pill tone={expired ? "ready" : "neutral"}>{expired ? "ready" : "active"}</Pill>
                            </div>
                          </div>
                        </div>
                      </div>
                    );
                  })
                )}
              </div>
            </section>

            {/* Vault strip */}
            <section className="mt-12">
              <Eyebrow>Vault</Eyebrow>
              <div className="inset-card rise mt-3 rounded-3xl p-6" style={{ animationDelay: "100ms" }}>
                <div className="grid grid-cols-3 gap-4">
                  <div>
                    <div className="text-xs text-mist">Deposits</div>
                    <div className="tnum mt-1 font-display text-lg font-bold">{tok(vault.totalDeposits)}</div>
                  </div>
                  <div>
                    <div className="text-xs text-mist">Reserved</div>
                    <div className="tnum mt-1 font-display text-lg font-bold">{tok(vault.reserved)}</div>
                  </div>
                  <div>
                    <div className="text-xs text-mist">Capacity</div>
                    <div className="tnum mt-1 font-display text-lg font-bold">{tok(vault.availableCapacity)}</div>
                  </div>
                </div>
                <div className="mt-5">
                  <div className="mb-1.5 flex justify-between text-[11px] text-mist">
                    <span>Utilization</span>
                    <span className="tnum">{(utilization * 100).toFixed(1)}%</span>
                  </div>
                  <ProgressBar pct={utilization} tone={utilization > 0.8 ? "action" : "mist"} />
                </div>
                <Link href="/vault" className="mt-4 inline-flex items-center gap-1 text-xs text-action hover:underline">
                  Back the vault, earn premiums <IconArrow className="h-3.5 w-3.5" />
                </Link>
              </div>
            </section>

            <p className="mt-10 text-center text-[11px] text-mist/70">
              All prices read from on-chain feeds · testnet prices are disclosed demo data
            </p>
          </>
        )}
      </main>
    </>
  );
}

function fmtCompactToken(value: bigint, decimals: number): string {
  const n = Number(formatUnits(value, decimals));
  if (n >= 1e6) return `${(n / 1e6).toFixed(2)}M`;
  if (n >= 1e4) return `${(n / 1e3).toFixed(1)}K`;
  return n.toLocaleString("en-US", { maximumFractionDigits: 2 });
}

function SkeletonRow() {
  return (
    <div className="inset-card flex items-center justify-between rounded-2xl px-4 py-3.5">
      <div className="flex items-center gap-3">
        <Skeleton className="h-9 w-9 rounded-xl" />
        <div className="space-y-1.5">
          <Skeleton className="h-3.5 w-24" />
          <Skeleton className="h-3 w-16" />
        </div>
      </div>
      <div className="space-y-1.5">
        <Skeleton className="ml-auto h-3.5 w-20" />
        <Skeleton className="ml-auto h-3 w-12" />
      </div>
    </div>
  );
}
