"use client";

import { useMemo, useState } from "react";
import { useReadContracts } from "wagmi";
import { parseUnits } from "viem";
import { WalletIcon } from "@/components/WalletIcon";
import { Skeleton } from "@/components/ui";
import { useDeployed, useAssets, type AssetView } from "@/lib/protocol";
import { noteAbi } from "@/lib/abis";
import { fmtPrice, fmtUsd18 } from "@/lib/format";

/**
 * The landing page's market board — the reference's "Top Gainers" grid, carrying live
 * numbers instead of decoration. Every value on a card is read from the chain at render
 * time: the price from the asset's registered feed, the cover cost from the note
 * contract's own quote() for one share. Nothing here is hardcoded; when the protocol is
 * not deployed on the visitor's chain the board says so rather than inventing figures.
 *
 * The period pill re-prices the board: cover cost is quoted for the selected duration.
 */

const DAY = 24n * 60n * 60n;
const LEVEL = 70n * 10n ** 16n; // the 70% tier — the widest, cheapest floor

const DURATIONS = [
  { label: "1 day", value: DAY },
  { label: "7 days", value: 7n * DAY },
  { label: "14 days", value: 14n * DAY },
  { label: "30 days", value: 30n * DAY },
];

export function LandingFloors() {
  const { deployed } = useDeployed();
  const { assets, isLoading } = useAssets();
  const [duration, setDuration] = useState(DURATIONS[0].value);

  const activeAssets = useMemo(() => assets.filter((a) => a.active), [assets]);

  // One batched read prices every active asset: quote() returns
  // [premiumUSD18, protectedUSD18, expiry] for one share at the 70% floor.
  const { data: quotes, isLoading: loadingQuotes } = useReadContracts({
    allowFailure: true,
    query: { enabled: !!deployed && activeAssets.length > 0 },
    contracts: deployed
      ? activeAssets.map((a) => ({
          address: deployed.note,
          abi: noteAbi,
          functionName: "quote",
          args: [a.token, parseUnits("1", a.decimals), LEVEL, duration] as const,
        }))
      : [],
  });

  const premiumByToken = useMemo(() => {
    const map = new Map<string, bigint | undefined>();
    activeAssets.forEach((a, i) => {
      const res = quotes?.[i];
      // The conditional contracts array (empty when not deployed) costs wagmi's inference
      // here, but quote() provably returns (premium, protected, expiry) — index 0 is the cost.
      map.set(a.token, res?.status === "success" ? (res.result as unknown as readonly bigint[])[0] : undefined);
    });
    return map;
  }, [activeAssets, quotes]);

  const durationLabel = DURATIONS.find((d) => d.value === duration)?.label ?? "1 day";

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="font-display text-xl font-bold tracking-tight">Top floors</h2>
        <div className="flex items-center gap-1 rounded-full bg-white py-1 pl-3.5 pr-2.5">
          <select
            value={String(duration)}
            onChange={(e) => setDuration(BigInt(e.target.value))}
            aria-label="Cover duration"
            className="cursor-pointer appearance-none bg-transparent text-xs font-bold text-black outline-none"
          >
            {DURATIONS.map((d) => (
              <option key={d.label} value={String(d.value)}>
                {d.label}
              </option>
            ))}
          </select>
          <span aria-hidden className="text-[9px] text-black">
            ▼
          </span>
        </div>
      </div>

      {!deployed && !isLoading ? (
        <p className="mt-8 rounded-3xl border border-line bg-surface px-6 py-10 text-center text-sm text-mist">
          Sherwood lives on Robinhood Chain testnet. Open the app there and this board reads
          live prices straight from the chain.
        </p>
      ) : isLoading ? (
        <div className="mt-8 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {[0, 1, 2].map((i) => (
            <Skeleton key={i} className="h-[420px] rounded-3xl" />
          ))}
        </div>
      ) : assets.length === 0 ? (
        <p className="mt-8 rounded-3xl border border-line bg-surface px-6 py-10 text-center text-sm text-mist">
          Nothing registered yet — the board fills as assets go on-chain.
        </p>
      ) : (
        <div className="mt-8 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {assets.map((a, i) => (
            <FloorCard
              key={a.token}
              asset={a}
              premiumUSD18={a.active ? premiumByToken.get(a.token) : undefined}
              durationLabel={durationLabel}
              index={i}
            />
          ))}
        </div>
      )}

      {deployed && activeAssets.length > 0 && loadingQuotes ? (
        <p className="mt-4 text-center text-[11px] text-mist">Reading cover costs from the chain…</p>
      ) : null}
    </div>
  );
}

/**
 * The three reference backdrops, in this app's palette: a green glow, charcoal scanlines,
 * and white. Assigned by position, cycling. The generated avatar carries the asset's mark.
 */
const POSTERS = [
  "bg-[radial-gradient(120%_120%_at_50%_0%,#2e4a00_0%,#0b1000_72%)]",
  "scanlines bg-[#141414]",
  "bg-white",
] as const;

function FloorCard({
  asset,
  premiumUSD18,
  durationLabel,
  index,
}: {
  asset: AssetView;
  premiumUSD18: bigint | undefined;
  durationLabel: string;
  index: number;
}) {
  const backdrop = POSTERS[index % POSTERS.length];
  const onWhite = backdrop === "bg-white";
  const floorPrice8 = asset.price8 !== undefined ? (asset.price8 * 70n) / 100n : undefined;

  return (
    <article className="inset-card rise flex flex-col rounded-3xl p-4" style={{ animationDelay: `${index * 60}ms` }}>
      <div
        className={`relative flex h-64 flex-col items-center justify-end overflow-hidden rounded-2xl pb-4 ${
          onWhite ? "border border-line" : ""
        } ${backdrop}`}
      >
        <WalletIcon
          seed={asset.symbol}
          background={null}
          palette={onWhite ? "ink" : "brand"}
          className="mb-3 h-24 w-24 drop-shadow-[0_16px_20px_rgba(0,0,0,0.35)]"
        />
        <span
          className={`rounded-lg border px-3 py-1 text-[13px] font-bold uppercase tracking-[0.14em] backdrop-blur-sm ${
            onWhite ? "border-black/20 text-black/85" : "border-white/30 text-white/85"
          }`}
        >
          {asset.symbol}
        </span>
      </div>

      <div className="px-2 pb-2 pt-5 text-center">
        <h3 className="font-display text-lg font-bold tracking-tight">{asset.name ?? asset.symbol}</h3>
        {asset.active ? (
          <>
            <div className="mt-2 flex items-center justify-center gap-1.5 text-xs text-mist">
              <span aria-hidden className="text-[10px] text-action">
                ◆
              </span>
              <span className="tnum text-ink">{fmtPrice(asset.price8)}</span>
              <span>· floor</span>
              <span className="tnum">{fmtPrice(floorPrice8)}</span>
            </div>
            <p className="tnum mt-1.5 text-[11px] text-mist">
              {premiumUSD18 !== undefined
                ? `${durationLabel} cover on 1 ${asset.symbol} from ${fmtUsd18(premiumUSD18)}`
                : "cover cost reads from the chain"}
            </p>
          </>
        ) : (
          <p className="mt-2 text-xs text-mist">coming soon — registered, not yet protectable</p>
        )}
      </div>
    </article>
  );
}
