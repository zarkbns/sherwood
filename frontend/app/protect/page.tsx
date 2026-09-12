"use client";

import { useState } from "react";
import { useAccount, useChainId, useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { formatUnits } from "viem";
import { Header } from "@/components/Header";
import { Empty, TxStatus } from "@/components/ui";
import { useDeployed, useAssets, settlementTokenFor, parseTokenAmount, usd18ToToken } from "@/lib/protocol";
import { noteAbi, erc20Abi } from "@/lib/abis";
import { fmtUsd18, fmtPrice, fmtExpiry, fmtToken } from "@/lib/format";

const LEVELS = [
  { label: "70%", value: 70n * 10n ** 16n },
  { label: "80%", value: 80n * 10n ** 16n },
  { label: "90%", value: 90n * 10n ** 16n },
];

const DURATIONS = [
  { label: "1 day", value: 24n * 60n * 60n },
  { label: "7 days", value: 7n * 24n * 60n * 60n },
  { label: "14 days", value: 14n * 24n * 60n * 60n },
  { label: "30 days", value: 30n * 24n * 60n * 60n },
];

export default function Protect() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { deployed } = useDeployed();
  const { assets } = useAssets();
  const st = settlementTokenFor(chainId);

  const [asset, setAsset] = useState<string>("");
  const [amount, setAmount] = useState<string>("");
  const [level, setLevel] = useState(LEVELS[1].value);
  const [duration, setDuration] = useState(DURATIONS[0].value);

  const selected = assets.find((a) => a.token === asset);
  const amountWei = selected ? parseTokenAmount(amount, selected.decimals) : 0n;

  // Position guard mirrored from the contract: create() reverts InsufficientPosition
  // unless the caller holds the protected amount. Block it in the UI, don't mint reverts.
  const held = selected?.balance;
  const holdsEnough = held === undefined || held >= amountWei;
  const overPosition = amountWei > 0n && held !== undefined && held < amountWei;

  // Live quote is read from the chain — the UI never prices anything itself.
  // The quote result is a tuple in ABI output order: [premiumUSD18, protectedUSD18, expiry].
  const { data: quote } = useReadContract({
    ...{ address: deployed?.note, abi: noteAbi },
    functionName: "quote",
    args: deployed && selected && amountWei > 0n ? [selected.token, amountWei, level, duration] : undefined,
    query: { enabled: !!deployed && !!selected && amountWei > 0n },
  });

  const premiumUSD18 = quote?.[0];
  const protectedUSD18 = quote?.[1];
  const quoteExpiry = quote?.[2];
  const premiumToken = premiumUSD18 !== undefined ? usd18ToToken(premiumUSD18, st?.decimals ?? 18) : 0n;

  const { data: allowance } = useReadContract({
    address: st?.address,
    abi: erc20Abi,
    functionName: "allowance",
    args: address && deployed ? [address, deployed.vault] : undefined,
    query: { enabled: !!address && !!deployed && !!st?.address },
  });

  const { writeContract, data: txHash, isPending, error } = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash: txHash });

  const needsApproval = quote && allowance !== undefined && allowance < premiumToken;
  const canCreate = isConnected && !!deployed && !!quote && holdsEnough && !needsApproval && !isPending && !receipt.isLoading;
  const canApprove = isConnected && !!deployed && !!quote && !!needsApproval && !isPending && !receipt.isLoading;

  function approve() {
    if (!deployed || !st) return;
    writeContract({
      address: st.address,
      abi: erc20Abi,
      functionName: "approve",
      args: [deployed.vault, premiumToken],
    });
  }

  function create() {
    if (!deployed || !selected) return;
    writeContract({
      address: deployed.note,
      abi: noteAbi,
      functionName: "create",
      args: [selected.token, amountWei, level, duration],
    });
  }

  const failReason = error
    ? /InsufficientPosition/.test(`${error.message} ${(error as { shortMessage?: string }).shortMessage ?? ""}`)
      ? "you must hold the stock you are protecting — reduce the amount"
      : error.message.slice(0, 120)
    : null;
  const state = isPending
    ? "Confirm in wallet…"
    : receipt.isLoading
      ? "Waiting for confirmation…"
      : receipt.isSuccess
        ? "Protection Note created — see Notes."
        : failReason
          ? `Failed: ${failReason}`
          : null;

  return (
    <>
      <Header />
      <main className="mx-auto max-w-5xl px-6 py-10">
        {!deployed ? (
          <Empty title="Not deployed on this network" body="Switch to Robinhood Chain testnet where Sherwood is deployed." />
        ) : assets.length === 0 ? (
          <Empty title="No registered assets" body="No stock tokens are registered on this chain yet." />
        ) : (
          <>
            <h1 className="font-display text-4xl font-bold tracking-tight">
              Protect<span className="text-action">.</span>
            </h1>
            <p className="mt-2 text-sm text-mist">
              Define your floor. The quote below is read live from the Chainlink-backed contract.
            </p>

            <div className="mt-8 grid grid-cols-1 gap-4 lg:grid-cols-5">
              <div className="inset-card space-y-6 rounded-3xl p-6 lg:col-span-3">
                <div>
                  <label className="text-xs uppercase tracking-widest text-mist">Asset</label>
                  <select
                    className="mt-2 w-full rounded-xl border border-line bg-surface-2 px-4 py-3 text-sm outline-none"
                    value={asset}
                    onChange={(e) => setAsset(e.target.value)}
                  >
                    <option value="">Select asset…</option>
                    {assets
                      .filter((a) => a.active)
                      .map((a) => (
                        <option key={a.token} value={a.token}>
                          {a.symbol} — live {fmtPrice(a.price8)}
                        </option>
                      ))}
                  </select>
                </div>

                <div>
                  <div className="flex items-baseline justify-between">
                    <label className="text-xs uppercase tracking-widest text-mist">Amount ({selected?.symbol ?? "tokens"})</label>
                    {selected && held !== undefined ? (
                      <button
                        type="button"
                        onClick={() => setAmount(formatUnits(held, selected.decimals))}
                        className="text-xs text-action hover:underline"
                      >
                        Protect max
                      </button>
                    ) : null}
                  </div>
                  <input
                    className="mt-2 w-full rounded-xl border border-line bg-surface-2 px-4 py-3 text-sm outline-none"
                    placeholder="0.00"
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                    inputMode="decimal"
                  />
                  {selected ? (
                    <p className={`mt-2 text-xs ${overPosition ? "text-fog" : "text-mist"}`}>
                      {held === undefined
                        ? "Connect a wallet to see your position."
                        : overPosition
                          ? `Position guard: you hold ${fmtToken(held, selected.decimals, selected.symbol)} — the contract rejects protecting more.`
                          : `You hold ${fmtToken(held, selected.decimals, selected.symbol)} — protection never leaves your wallet.`}
                    </p>
                  ) : null}
                </div>

                <div>
                  <label className="text-xs uppercase tracking-widest text-mist">Protection level</label>
                  <div className="mt-2 grid grid-cols-3 gap-2">
                    {LEVELS.map((l) => (
                      <button
                        key={l.label}
                        onClick={() => setLevel(l.value)}
                        className={`rounded-xl border px-4 py-3 text-sm ${level === l.value ? "border-action text-ink" : "border-line text-fog hover:text-ink"}`}
                      >
                        {l.label}
                      </button>
                    ))}
                  </div>
                </div>

                <div>
                  <label className="text-xs uppercase tracking-widest text-mist">Duration</label>
                  <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
                    {DURATIONS.map((d) => (
                      <button
                        key={d.label}
                        onClick={() => setDuration(d.value)}
                        className={`rounded-xl border px-4 py-3 text-sm ${duration === d.value ? "border-action text-ink" : "border-line text-fog hover:text-ink"}`}
                      >
                        {d.label}
                      </button>
                    ))}
                  </div>
                </div>
              </div>

              <div className="inset-card rounded-3xl p-6 lg:col-span-2">
                <div className="text-xs uppercase tracking-widest text-mist">Terms</div>
                {quote ? (
                  <dl className="mt-4 space-y-3 text-sm">
                    <Row label="Position value" value={fmtUsd18((amountWei * (selected?.price8 ?? 0n)) / 10n ** 8n)} />
                    <Row label="Entry price (Chainlink)" value={fmtPrice(selected?.price8)} />
                    <Row label="Your floor" value={fmtUsd18(protectedUSD18)} />
                    <Row label="Max payout" value={fmtUsd18(protectedUSD18)} />
                    <Row label="Premium due" value={fmtUsd18(premiumUSD18)} />
                    <Row label="Expires" value={fmtExpiry(quote[2])} />
                  </dl>
                ) : (
                  <p className="mt-4 text-sm text-mist">Pick an asset and amount to get a live quote.</p>
                )}

                <div className="mt-6 space-y-3">
                  {needsApproval ? (
                    <button onClick={approve} disabled={!canApprove} className="btn-action w-full rounded-xl px-4 py-3 text-sm">
                      Approve {st?.symbol ?? "token"}
                    </button>
                  ) : null}
                  <button onClick={create} disabled={!canCreate} className="btn-action w-full rounded-xl px-4 py-3 text-sm">
                    {needsApproval ? "Approval required first" : overPosition ? "Exceeds your position" : "Buy Protection Note"}
                  </button>
                  <TxStatus state={state} />
                </div>
              </div>
            </div>
          </>
        )}
      </main>
    </>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <dt className="text-mist">{label}</dt>
      <dd className="font-display font-bold">{value}</dd>
    </div>
  );
}
