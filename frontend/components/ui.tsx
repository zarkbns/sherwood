import type { ReactNode } from "react";
import Link from "next/link";

/* --------------------------------------------------------------- icons —
 * One family: 1.5px stroke, round caps, currentColor, 20px grid. No emoji,
 * no mixing. Icons punctuate; they never decorate. */

type IconProps = { className?: string };

const stroke = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.5,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

export function IconShield({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" className={className} aria-hidden>
      <path {...stroke} d="M10 2.5 16.5 5v4.2c0 4-2.7 6.8-6.5 8.3-3.8-1.5-6.5-4.3-6.5-8.3V5L10 2.5Z" />
      <path {...stroke} d="M7 10l2 2 4-4.5" />
    </svg>
  );
}

export function IconGauge({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" className={className} aria-hidden>
      <path {...stroke} d="M3.5 14a8 8 0 1 1 13 0" />
      <path {...stroke} d="M10 13.5 13 7.5" />
      <circle {...stroke} cx="10" cy="14.5" r="1.2" />
    </svg>
  );
}

export function IconFile({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" className={className} aria-hidden>
      <path {...stroke} d="M5 2.5h6.5L16 7v10.5H5V2.5Z" />
      <path {...stroke} d="M11 2.5V7h4.5M7.5 11h5M7.5 14h5" />
    </svg>
  );
}

export function IconVault({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" className={className} aria-hidden>
      <rect {...stroke} x="2.5" y="3.5" width="15" height="13" rx="2.5" />
      <circle {...stroke} cx="10" cy="10" r="3" />
      <path {...stroke} d="M10 7V5.5M10 14.5V13M13 10h1.5" />
    </svg>
  );
}

export function IconWallet({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" className={className} aria-hidden>
      <path {...stroke} d="M3 6.5A2.5 2.5 0 0 1 5.5 4h9A2.5 2.5 0 0 1 17 6.5v8A2.5 2.5 0 0 1 14.5 17h-9A2.5 2.5 0 0 1 3 14.5v-8Z" />
      <path {...stroke} d="M3 8h14M13.5 12.5h1.5" />
    </svg>
  );
}

export function IconCheck({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" className={className} aria-hidden>
      <circle {...stroke} cx="10" cy="10" r="7.5" />
      <path {...stroke} d="M6.5 10.5l2.3 2.3L13.5 7.5" />
    </svg>
  );
}

export function IconAlert({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" className={className} aria-hidden>
      <circle {...stroke} cx="10" cy="10" r="7.5" />
      <path {...stroke} d="M10 6v5M10 13.5v.5" />
    </svg>
  );
}

export function IconArrow({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" className={className} aria-hidden>
      <path {...stroke} d="M4 10h11M11.5 6 15.5 10l-4 4" />
    </svg>
  );
}

export function IconClock({ className }: IconProps) {
  return (
    <svg viewBox="0 0 20 20" className={className} aria-hidden>
      <circle {...stroke} cx="10" cy="10" r="7.5" />
      <path {...stroke} d="M10 5.5V10l3 1.8" />
    </svg>
  );
}

/* --------------------------------------------------------------- type */

/** All-caps signage label — wide tracking, mist. The section voice. */
export function Eyebrow({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`text-[11px] uppercase tracking-[0.16em] text-mist ${className}`}>{children}</div>
  );
}

/* --------------------------------------------------------------- surfaces */

export function StatCard({
  label,
  value,
  sub,
  delay = 0,
}: {
  label: string;
  value: string;
  sub?: string;
  delay?: number;
}) {
  return (
    <div className="inset-card rise rounded-3xl p-6" style={{ animationDelay: `${delay}ms` }}>
      <Eyebrow>{label}</Eyebrow>
      <div className="tnum mt-3 font-display text-[28px] leading-none font-bold tracking-tight text-ink">
        {value}
      </div>
      {sub ? <div className="mt-2 text-xs text-mist">{sub}</div> : null}
    </div>
  );
}

export function Pill({ tone, children }: { tone: "neutral" | "ready" | "done"; children: ReactNode }) {
  const cls =
    tone === "ready"
      ? "border-action/50 text-action"
      : tone === "done"
        ? "border-line text-mist"
        : "border-line text-fog";
  return (
    <span className={`rounded-full border px-3 py-1 text-[11px] uppercase tracking-[0.08em] ${cls}`}>
      {children}
    </span>
  );
}

/** Thin progress rail — reserved for data (expiry, utilization), never decoration. */
export function ProgressBar({ pct, tone = "action" }: { pct: number; tone?: "action" | "mist" }) {
  const width = Math.min(100, Math.max(0, pct * 100));
  return (
    <div className="h-1 w-full overflow-hidden rounded-full bg-white/5">
      <div
        className={`bar-fill h-full rounded-full ${tone === "action" ? "bg-action" : "bg-mist/50"}`}
        style={{ width: `${width}%` }}
      />
    </div>
  );
}

/* --------------------------------------------------------------- controls */

export function SegmentedControl<T extends bigint>({
  options,
  value,
  onChange,
  delay = 0,
}: {
  options: { label: string; value: T; hint?: string }[];
  value: T;
  onChange: (v: T) => void;
  delay?: number;
}) {
  return (
    <div
      role="radiogroup"
      className="rise grid gap-1.5 rounded-2xl border border-line bg-surface p-1.5"
      style={{ gridTemplateColumns: `repeat(${options.length}, minmax(0, 1fr))`, animationDelay: `${delay}ms` }}
    >
      {options.map((o) => {
        const active = o.value === value;
        return (
          <button
            key={o.label}
            type="button"
            role="radio"
            aria-checked={active}
            onClick={() => onChange(o.value)}
            className={`rounded-xl px-2 py-2.5 text-center transition-colors duration-150 ${
              active ? "bg-surface-3 text-ink" : "text-fog hover:bg-white/[0.04] hover:text-ink"
            }`}
          >
            <span className="block text-sm">{o.label}</span>
            {o.hint ? <span className="tnum mt-0.5 block text-[10px] text-mist">{o.hint}</span> : null}
          </button>
        );
      })}
    </div>
  );
}

/* --------------------------------------------------------------- states */

export function Skeleton({ className = "" }: { className?: string }) {
  return <div className={`skeleton rounded-xl ${className}`} />;
}

export function EmptyState({
  icon,
  title,
  body,
  actionHref,
  actionLabel,
}: {
  icon: ReactNode;
  title: string;
  body: string;
  actionHref?: string;
  actionLabel?: string;
}) {
  return (
    <div className="inset-card rise rounded-3xl p-10 text-center">
      <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl border border-line text-mist">
        {icon}
      </div>
      <div className="mt-4 font-display text-xl font-bold tracking-tight">{title}</div>
      <p className="mx-auto mt-2 max-w-md text-sm text-mist">{body}</p>
      {actionHref && actionLabel ? (
        <Link
          href={actionHref}
          className="btn-action mt-6 inline-flex items-center gap-2 rounded-full px-5 py-2.5 text-sm"
        >
          {actionLabel}
          <IconArrow className="h-4 w-4" />
        </Link>
      ) : null}
    </div>
  );
}

export type TxFail = { kind: "pending" | "busy" | "success" | "error"; text: string };

export function TxStatus({ state }: { state: TxFail | null }) {
  if (!state) return null;
  const icon =
    state.kind === "success" ? (
      <IconCheck className="h-4 w-4 text-action" />
    ) : state.kind === "error" ? (
      <IconAlert className="h-4 w-4 text-fog" />
    ) : (
      <IconClock className="h-4 w-4 text-mist" />
    );
  return (
    <p className="rise mt-3 flex items-center justify-center gap-2 text-sm text-fog">
      {icon}
      {state.text}
    </p>
  );
}
