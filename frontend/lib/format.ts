import { formatUnits } from "viem";

/** Chainlink price (8 dec) -> dollars, e.g. 100e8 -> "$100.00" */
export function fmtPrice(price8: bigint | undefined): string {
  if (price8 === undefined) return "—";
  const dollars = Number(price8) / 1e8;
  return `$${dollars.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** USD-18 -> dollars string, e.g. 12.5e18 -> "$12.50" */
export function fmtUsd18(value: bigint | undefined): string {
  if (value === undefined) return "—";
  return `$${Number(formatUnits(value, 18)).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

/** Settlement-token units -> token string using the token's decimals */
export function fmtToken(value: bigint | undefined, decimals: number, symbol?: string): string {
  if (value === undefined) return "—";
  const num = Number(formatUnits(value, decimals)).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  return symbol ? `${num} ${symbol}` : num;
}

export function fmtExpiry(expiry: bigint | number): string {
  const ms = Number(expiry) * 1000;
  return new Date(ms).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

export function isExpired(expiry: bigint | number): boolean {
  return Date.now() / 1000 >= Number(expiry);
}

/** USD-18 -> human dollars with magnitude suffixes: $1.4M, $4.99, $0.56. */
export function fmtUsd18Compact(value: bigint | undefined): string {
  if (value === undefined) return "—";
  const n = Number(formatUnits(value, 18));
  const abs = Math.abs(n);
  if (abs >= 1e9) return `$${(n / 1e9).toLocaleString("en-US", { maximumFractionDigits: 2 })}B`;
  if (abs >= 1e6) return `$${(n / 1e6).toLocaleString("en-US", { maximumFractionDigits: 2 })}M`;
  if (abs >= 1e4) return `$${(n / 1e3).toLocaleString("en-US", { maximumFractionDigits: 1 })}K`;
  return fmtUsd18(value);
}

/** Token amount with trimmed zeros — 15 TSLA, not 15.00; 0.38 stays. */
export function fmtQty(value: bigint | undefined, decimals: number, symbol?: string): string {
  if (value === undefined) return "—";
  const num = Number(formatUnits(value, decimals)).toLocaleString("en-US", {
    maximumFractionDigits: 4,
  });
  return symbol ? `${num} ${symbol}` : num;
}

/** Human countdown from now to a unix expiry: "2d 6h left", "3h left", "45m left". */
export function fmtCountdown(expiry: bigint | number): string {
  const secs = Number(expiry) - Math.floor(Date.now() / 1000);
  if (secs <= 0) return "ready to settle";
  const d = Math.floor(secs / 86400);
  const h = Math.floor((secs % 86400) / 3600);
  const m = Math.floor((secs % 3600) / 60);
  if (d > 0) return `${d}d ${h}h left`;
  if (h > 0) return `${h}h left`;
  return `${Math.max(m, 1)}m left`;
}

/** 0..1 progress of [start, end] at "now"; clamped. */
export function progressFraction(start: bigint | number, end: bigint | number): number {
  const s = Number(start);
  const e = Number(end);
  const now = Date.now() / 1000;
  if (e <= s) return 1;
  return Math.min(1, Math.max(0, (now - s) / (e - s)));
}
