import type { ReactNode } from "react";

/**
 * The dashboard's stat strip — a row of small readout chips.
 *
 * Values are passed in, never hardcoded here: the reference mock listed market-wide
 * numbers (cryptos tracked, exchanges, market cap) that have no counterpart in this
 * protocol, so the same visual slot carries what the chain can actually answer.
 */
export function StatStrip({ items }: { items: { label: string; value: string; tone?: "ink" | "action" | "muted" }[] }) {
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
      {items.map((it, i) => (
        <div
          key={it.label}
          className="rise rounded-xl bg-surface px-4 py-3 text-center"
          style={{ animationDelay: `${i * 40}ms` }}
        >
          <div className="text-[11px] leading-tight text-mist">{it.label}</div>
          <div
            className={`tnum mt-1 truncate text-sm ${
              it.tone === "action" ? "text-action" : it.tone === "muted" ? "text-mist" : "text-ink"
            }`}
          >
            {it.value}
          </div>
        </div>
      ))}
    </div>
  );
}

/**
 * A panel: the reference's rounded card. Kept as a component so the dashboard reads as
 * composition rather than a wall of divs, and so card padding/radius stay consistent.
 */
export function Panel({
  title,
  action,
  children,
  className = "",
  bodyClassName = "",
}: {
  title?: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
  bodyClassName?: string;
}) {
  return (
    <section className={`inset-card rise flex flex-col rounded-3xl p-6 ${className}`}>
      {title ? (
        <header className="flex items-center justify-between gap-3">
          <h2 className="font-display text-lg font-semibold tracking-tight">{title}</h2>
          {action}
        </header>
      ) : null}
      <div className={`${title ? "mt-5" : ""} ${bodyClassName}`}>{children}</div>
    </section>
  );
}
