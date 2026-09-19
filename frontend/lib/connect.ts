import type { Connector } from "wagmi";

/**
 * Connector selection for the single-button connect flow. The rule is simple: tap
 * Connect wallet, and WalletConnect's own chooser opens — it lists the real wallets and
 * knows how to deep-link into them on mobile, which is a better answer than Sherwood
 * guessing from injected-provider flags. When no WalletConnect project id is configured
 * (a clean checkout without env), the injected connector is the honest fallback: still
 * one tap, still no picker screen.
 */
export function connectTarget(connectors: readonly Connector[]): Connector | null {
  return (
    connectors.find((c) => c.id === "walletConnect") ??
    connectors.find((c) => c.id === "injected") ??
    connectors[0] ??
    null
  );
}

/**
 * A closed or cancelled modal is not a failure to report as an error — it is the user
 * choosing not to continue, and the only useful message is "tap again". Everything else
 * (relay down, wallet app missing the deep link, rejected session) keeps its message so
 * the user has something specific to act on.
 */
export function describeConnectError(err: Error | null): { cancelled: boolean; message: string } | null {
  if (!err) return null;
  const text = err.message || "";
  const lower = text.toLowerCase();
  if (lower.includes("user rejected") || lower.includes("rejected") || lower.includes("closed") || lower.includes("dismissed")) {
    return { cancelled: true, message: "Disconnected before the session was approved — tap again." };
  }
  if (lower.includes("no projects found") || lower.includes("invalid project")) {
    return { cancelled: false, message: "WalletConnect is not configured for this deployment." };
  }
  return { cancelled: false, message: text.slice(0, 140) || "The wallet could not complete the connection." };
}
