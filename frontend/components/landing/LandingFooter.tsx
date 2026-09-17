import Link from "next/link";
import { WalletIcon } from "@/components/WalletIcon";
import { robinhoodTestnet } from "@/lib/chain";
import { addressesFor } from "@/lib/addresses";

/**
 * The landing footer, on the reference's three-column shape. No mailing list and no
 * cookie theater — the slots carry what a visitor can actually check: the contracts on
 * the explorer, the protocol's settlement guarantees, and the testnet disclosure. The
 * generated guardian peeks over the edge on wide screens, the way the reference's mascot
 * does.
 */
export function LandingFooter() {
  const registry = addressesFor(robinhoodTestnet.id)?.registry;
  const explorerHref = registry
    ? `${robinhoodTestnet.blockExplorers.default.url}/address/${registry}`
    : robinhoodTestnet.blockExplorers.default.url;

  return (
    <footer className="relative mx-auto w-full max-w-6xl border-t border-line/70 px-5 pb-16 pt-12 sm:px-6">
      <div className="absolute -top-16 right-[22%] hidden lg:block">
        <WalletIcon
          seed="sherwood-guardian"
          className="h-24 w-24 rounded-full border-4 border-canvas shadow-[0_-10px_30px_rgba(0,0,0,0.8)]"
        />
      </div>

      <div className="grid gap-10 text-center sm:grid-cols-3 sm:text-left">
        <div className="flex flex-col items-center gap-3 sm:items-start">
          <span className="flex gap-1.5" aria-hidden>
            <span className="h-2.5 w-2.5 rounded-full border border-line" />
            <span className="h-2.5 w-2.5 rounded-full border border-line" />
            <span className="h-2.5 w-2.5 rounded-full border border-line" />
          </span>
          <span className="text-[11px] text-mist">© 2026 Sherwood</span>
          <Link href={explorerHref} target="_blank" rel="noreferrer" className="text-[11px] uppercase tracking-[0.14em] text-fog transition-colors hover:text-action">
            View contracts
          </Link>
        </div>

        <div className="flex flex-col items-center gap-2">
          <span className="text-[11px] uppercase tracking-[0.14em] text-mist">Protocol</span>
          <span className="text-[11px] text-mist">Chainlink-settled · collateral-backed</span>
          <span className="tnum text-[11px] text-mist">
            {robinhoodTestnet.name} · {robinhoodTestnet.id}
          </span>
        </div>

        <div className="flex flex-col items-center gap-2 sm:items-end">
          <span className="text-[11px] uppercase tracking-[0.14em] text-mist">Testnet</span>
          <span className="max-w-[240px] text-[11px] leading-relaxed text-mist">
            Nothing here is a real position, a real price, or a real payout.
          </span>
        </div>
      </div>
    </footer>
  );
}
