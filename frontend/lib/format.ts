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
