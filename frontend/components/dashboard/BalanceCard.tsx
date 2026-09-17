"use client";

import { Eyebrow } from "@/components/ui";
import { fmtUsd18, fmtPrice } from "@/lib/format";

/**
 * The portfolio card.
 *
 * The reference mock drew a price sparkline with 1D/5D/1M/1Y filters. Nothing on-chain
 * stores price history — the demo feeds only move when the owner writes them — so a line
 * like that would either be invented or flat and empty. This shows the one comparison the
 * protocol can actually answer per position: where today's verified price sits against
 * the floor you own. Above the floor your protection is simply idle; below it, settlement
 * pays the gap.
 */

export type CoverageItem = {
  token: string;
  symbol: string;
  name: string | undefined;
  price8: bigint | undefined;
  /** entryPrice × level, i.e. the price at which the payout starts. undefined = no active note. */
  floorPrice8: bigint | undefined;
  /** The note's expiry, for context when a floor exists. */
  expiry: bigint | undefined;
};

export function BalanceCard({
  totalValueUSD18,
  heldCount,
  coverage,
}: {
  totalValueUSD18: bigint;
  heldCount: number;
  coverage: CoverageItem[];
}) {
  return (
    <div className="flex h-full flex-col">
      <Eyebrow>Portfolio value</Eyebrow>
      <div className="tnum mt-2 font-display text-4xl font-bold leading-none tracking-tight">
        {fmtUsd18(totalValueUSD18)}
      </div>
      <p className="mt-2 text-xs text-mist">
        {heldCount === 0
          ? "No stock positions yet — protection needs something to protect."
          : `${heldCount} position${heldCount === 1 ? "" : "s"} · priced from the registered feeds`}
      </p>

      <div className="mt-6 flex-1">
        <Eyebrow>Position vs floor</Eyebrow>
        {coverage.length === 0 ? (
          <p className="mt-3 text-xs text-mist">
            Rows appear here once you hold a registered asset; a bar appears once a note sets a floor on it.
          </p>
        ) : (
          <div className="mt-3 space-y-4">
            {coverage.map((c) => {
              const price = c.price8;
              const floor = c.floorPrice8;
              // Above floor: protection is idle, show how much headroom. Below: payout is live.
              const pct = price !== undefined && floor !== undefined && floor > 0n ? Number((price * 100n) / floor) : undefined;
              const belowFloor = pct !== undefined && pct < 100;
              // Bar is scaled against 150% so a large headroom does not pin to full width.
              const width = pct === undefined ? 0 : Math.max(3, Math.min(100, (pct / 150) * 100));
              return (
                <div key={c.token}>
                  <div className="flex items-baseline justify-between gap-3 text-xs">
                    <span className="text-ink">
                      {c.symbol}
                      {c.name ? <span className="ml-2 text-mist">{c.name}</span> : null}
                    </span>
                    <span className="tnum text-mist">
                      {price !== undefined ? fmtPrice(price) : "—"}
                      {floor !== undefined ? <span className="text-fog"> vs {fmtPrice(floor)} floor</span> : null}
                    </span>
                  </div>

                  {floor === undefined ? (
                    <p className="mt-1 text-[11px] text-mist">No protection on this one yet — no floor set.</p>
                  ) : (
                    <>
                      <div className="mt-1.5 h-1.5 w-full overflow-hidden rounded-full bg-white/5">
                        <div className="h-full w-full">
                          <div
                            className={`bar-fill h-full rounded-full ${belowFloor ? "bg-pending" : "bg-action"}`}
                            style={{ width: `${width}%` }}
                          />
                        </div>
                      </div>
                      <p className={`tnum mt-1 text-[11px] ${belowFloor ? "text-pending" : "text-mist"}`}>
                        {belowFloor
                          ? `Under your floor — this one pays out the gap${c.expiry ? ` · expires in ${describeExpiry(c.expiry)}` : ""}`
                          : `${pct !== undefined ? pct - 100 : 0}% above your floor — nothing to pay yet${
                              c.expiry ? ` · expires in ${describeExpiry(c.expiry)}` : ""
                            }`}
                      </p>
                    </>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

/** Short human duration until an expiry timestamp, or "expired". */
function describeExpiry(expiry: bigint): string {
  const seconds = Number(expiry) - Math.floor(Date.now() / 1000);
  if (seconds <= 0) return "expired — settle to release the reserve";
  const days = Math.floor(seconds / 86_400);
  const hours = Math.floor((seconds % 86_400) / 3_600);
  if (days > 0) return `${days}d ${hours}h`;
  const mins = Math.floor((seconds % 3_600) / 60);
  return `${hours}h ${mins}m`;
}
