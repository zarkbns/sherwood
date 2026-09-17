import { Eyebrow } from "@/components/ui";
import { NETWORK, FAUCET_REACHABLE, MAINNET_WARNING } from "@/lib/network";

/**
 * The network card: which chain this app talks to, and where testnet gas comes from.
 *
 * Exists because Robinhood Chain has two real deployments — testnet 46630 and mainnet 4663 —
 * and the failure mode is silent: send ETH to the wrong one and the app simply never sees it,
 * with nothing on screen explaining why. The chain ID and RPC are shown for adding the network
 * by hand, and the warning is explicit rather than implied.
 */
export function NetworkPanel() {
  return (
    <div className="inset-card rise rounded-3xl p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <Eyebrow>Network</Eyebrow>
          <div className="mt-2 font-display text-lg font-semibold tracking-tight">{NETWORK.name}</div>
          <div className="tnum mt-1 text-xs text-mist">chain ID {NETWORK.chainId}</div>
        </div>
        <div className="text-right">
          <Eyebrow>Testnet funds</Eyebrow>
          <a
            href={NETWORK.docs}
            target="_blank"
            rel="noreferrer"
            className="mt-2 block text-xs text-action hover:underline"
          >
            Robinhood Chain docs ↗
          </a>
          <p className="mt-1 max-w-[22rem] text-[11px] leading-relaxed text-mist">
            {FAUCET_REACHABLE
              ? "The official faucet funds testnet gas."
              : "The faucet host in Robinhood's docs did not respond when checked on 2026-09-17, so it is not linked as a working source. The docs page above explains how to connect."}
          </p>
        </div>
      </div>

      <dl className="mt-5 grid grid-cols-1 gap-3 text-xs sm:grid-cols-2">
        <div>
          <dt className="text-mist">RPC endpoint</dt>
          <dd className="tnum mt-0.5 break-all text-ink">{NETWORK.rpcUrl}</dd>
        </div>
        <div>
          <dt className="text-mist">Explorer</dt>
          <dd className="mt-0.5 break-all">
            <a href={NETWORK.explorer} target="_blank" rel="noreferrer" className="text-action hover:underline">
              {NETWORK.explorer.replace("https://", "")} ↗
            </a>
          </dd>
        </div>
      </dl>

      <p className="mt-5 rounded-2xl border border-pending/40 bg-pending/5 px-4 py-3 text-[11px] leading-relaxed text-fog">
        {MAINNET_WARNING} Mainnet is {NETWORK.mainnet.name} at chain ID {NETWORK.mainnet.chainId} (
        {NETWORK.mainnet.rpcUrl}) — this app does not use it.
      </p>
    </div>
  );
}
