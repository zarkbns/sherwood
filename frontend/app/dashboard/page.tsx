"use client";

import { useAccount, useBalance } from "wagmi";
import { formatUnits } from "viem";
import Link from "next/link";
import { Header } from "@/components/Header";
import { StatStrip, Panel } from "@/components/dashboard/StatStrip";
import { BalanceCard, type CoverageItem } from "@/components/dashboard/BalanceCard";
import { NetworkPanel } from "@/components/dashboard/NetworkPanel";
import { ProtectFlow } from "@/components/ProtectFlow";
import { Eyebrow, EmptyState, Pill, Skeleton, IconShield, IconFile, IconArrow } from "@/components/ui";
import { useDeployed, useAssets, useNotes, useVaultStats, settlementTokenFor } from "@/lib/protocol";
import { fmtUsd18, fmtUsd18Compact, fmtQty, fmtPrice, fmtCountdown, isExpired } from "@/lib/format";

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

  // Native gas balance. Read separately from the settlement token because it is not an ERC20
  // and never enters the registry — it exists here so a user can see why a transaction can
  // fail for gas while their stock balances look healthy.
  const { data: nativeBalance } = useBalance({
    address,
    query: { enabled: !!address },
  });

  const held = assets.filter((a) => a.balance !== undefined && a.balance > 0n);
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

  // Floor coverage: where each held asset's live price sits against the floor of an active
  // note on it. floor price = entryPrice × level, which is where payouts begin.
  const coverage: CoverageItem[] = held.map((a) => {
    const note = active.find((n) => n.asset.toLowerCase() === a.token.toLowerCase());
    return {
      token: a.token,
      symbol: a.symbol,
      name: a.name,
      price8: a.price8,
      floorPrice8: note ? (note.entryPrice * note.level) / 10n ** 18n : undefined,
      expiry: note?.expiry,
    };
  });

  const stats = [
    { label: "Stocks listed", value: String(assets.length) },
    { label: "Protection active", value: String(active.length), tone: active.length > 0 ? ("action" as const) : ("muted" as const) },
    { label: "Your floor", value: isConnected ? fmtUsd18Compact(totalProtected) : "—" },
    { label: "In the vault", value: tok(vault.totalDeposits) },
    { label: "Locked for payouts", value: tok(vault.reserved) },
    { label: "Vault in use", value: `${(utilization * 100).toFixed(1)}%` },
  ];

  if (!deployed) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-5xl px-5 pb-28 pt-8 sm:px-6 sm:pb-14 sm:pt-12">
          <EmptyState
            icon={<IconShield className="h-6 w-6" />}
            title="Not deployed on this network"
            body="Sherwood is live on Robinhood Chain testnet only. Switch networks to continue — addresses are set at deploy time."
          />
        </main>
      </>
    );
  }

  return (
    <>
      <Header />
      <main className="mx-auto max-w-6xl px-5 pb-28 pt-6 sm:px-6 sm:pb-14 sm:pt-8">
        <StatStrip items={stats} />

        {/* Two columns: protection on the left, portfolio on the right — more breathing
            room than the old three-column grid. Wallet access lives in the header menu. */}
        <div className="mt-5 grid grid-cols-1 items-stretch gap-4 lg:grid-cols-2">
          <Panel title="Buy protection" className="lg:col-span-1" bodyClassName="flex-1 flex flex-col">
            <ProtectFlow variant="card" />
          </Panel>

          <Panel
            title="Portfolio"
            className="lg:col-span-1"
            bodyClassName="flex-1"
            action={
              <Link href="/notes" className="inline-flex items-center gap-1 text-xs text-action hover:underline">
                Notes <IconArrow className="h-3.5 w-3.5" />
              </Link>
            }
          >
            {loadingAssets ? (
              <div className="space-y-3">
                <Skeleton className="h-10 w-40" />
                <Skeleton className="h-16 w-full" />
                <Skeleton className="h-16 w-full" />
              </div>
            ) : (
              <BalanceCard totalValueUSD18={positionValue} heldCount={held.length} coverage={coverage} />
            )}
          </Panel>
        </div>

        {/* Active protection — kept below the grid: the reference has no equivalent, but
            losing sight of live notes from the dashboard would be a step backwards. */}
        <section className="mt-10">
          <div className="flex items-baseline justify-between">
            <Eyebrow>Active protection</Eyebrow>
            <Link href="/notes" className="inline-flex items-center gap-1 text-xs text-action hover:underline">
              All notes <IconArrow className="h-3.5 w-3.5" />
            </Link>
          </div>
          <div className="mt-3 space-y-2">
            {loadingNotes ? (
              <Skeleton className="h-16 w-full rounded-2xl" />
            ) : active.length === 0 ? (
              <EmptyState
                icon={<IconFile className="h-6 w-6" />}
                title="Nothing protected yet"
                body="Pick a stock you own, choose how much to cover and for how long. You keep every gain above your floor."
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
                    className="inset-card rise flex flex-wrap items-center justify-between gap-4 rounded-2xl px-4 py-4"
                    style={{ animationDelay: `${i * 50}ms` }}
                  >
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-display text-sm font-bold tracking-tight">
                          Protection #{n.id.toString()}
                        </span>
                        <Pill tone={expired ? "ready" : "neutral"}>
                          {expired ? "settle now" : fmtCountdown(n.expiry)}
                        </Pill>
                      </div>
                      <div className="tnum mt-1 text-xs text-mist">
                        {fmtQty(n.amount, asset?.decimals ?? 18, asset?.symbol ?? "")} · floor{" "}
                        {fmtUsd18(n.protectedUSD18)} · bought at {fmtPrice(n.entryPrice)}
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="tnum text-sm text-ink">{fmtUsd18(n.premiumUSD18)}</div>
                      <div className="text-xs text-mist">you paid</div>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </section>

        {/* Vault — backing capital, one line of context. */}
        <section className="mt-10">
          <div className="flex items-baseline justify-between">
            <Eyebrow>Vault</Eyebrow>
            <Link href="/vault" className="inline-flex items-center gap-1 text-xs text-action hover:underline">
              Back the vault <IconArrow className="h-3.5 w-3.5" />
            </Link>
          </div>
          <div className="inset-card rise mt-3 rounded-3xl p-6">
            <div className="flex flex-wrap items-end justify-between gap-4">
              <div>
                <div className="text-xs text-mist">Locked for payouts · reserved collateral</div>
                <div className="tnum mt-1 font-display text-2xl font-bold tracking-tight">
                  {tok(vault.reserved)} <span className="text-sm font-normal text-mist">of {tok(vault.totalDeposits)} in the vault</span>
                </div>
              </div>
              <div className="w-full sm:w-64">
                <div className="flex items-baseline justify-between text-xs text-mist">
                  <span>Vault in use</span>
                  <span className="tnum">{(utilization * 100).toFixed(1)}%</span>
                </div>
                <div className="mt-2">
                  <div className="h-1.5 w-full overflow-hidden rounded-full bg-white/5">
                    <div
                      className="bar-fill h-full rounded-full bg-action"
                      style={{ width: `${Math.min(100, utilization * 100)}%` }}
                    />
                  </div>
                </div>
                <p className="mt-2 text-[11px] text-mist">
                  {isConnected ? `${fmtUsd18Compact(premiumSpent)} paid in costs across your protections.` : "Connect to see what you've paid in costs."}
                </p>
              </div>
            </div>
            <p className="mt-4 text-[11px] leading-relaxed text-mist">
              All prices read from on-chain feeds; testnet prices are disclosed demo data.
            </p>
          </div>
        </section>

        {/* Network — which chain this is, and why mainnet ETH will not fund it. */}
        <section className="mt-10">
          <NetworkPanel />
        </section>
      </main>
    </>
  );
}
