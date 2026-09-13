"use client";

import { useState } from "react";
import { useAccount, useChainId, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { formatUnits } from "viem";
import { Header } from "@/components/Header";
import { TxStatus, SegmentedControl, Eyebrow, EmptyState, IconShield, type TxFail } from "@/components/ui";
import { useDeployed, useAssets, settlementTokenFor, parseTokenAmount, usd18ToToken } from "@/lib/protocol";
import { noteAbi, erc20Abi } from "@/lib/abis";
import { fmtUsd18, fmtPrice, fmtExpiry, fmtQty } from "@/lib/format";

const DAY = 24n * 60n * 60n;

const LEVELS = [
  { label: "70%", value: 70n * 10n ** 16n, hint: "covers 30% drops" },
  { label: "80%", value: 80n * 10n ** 16n, hint: "covers 20% drops" },
  { label: "90%", value: 90n * 10n ** 16n, hint: "covers 10% drops" },
];

const DURATIONS = [
  { label: "1 day", value: DAY },
  { label: "7 days", value: 7n * DAY },
  { label: "14 days", value: 14n * DAY },
  { label: "30 days", value: 30n * DAY },
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
  const premiumToken = premiumUSD18 !== undefined ? usd18ToToken(premiumUSD18, st?.decimals ?? 6) : 0n;

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
  const txState: TxFail | null = isPending
    ? { kind: "pending", text: "Confirm in wallet…" }
    : receipt.isLoading
      ? { kind: "busy", text: "Waiting for confirmation…" }
      : receipt.isSuccess
        ? { kind: "success", text: "Protection Note created — see Notes" }
        : failReason
          ? { kind: "error", text: `Failed: ${failReason}` }
          : null;

  if (!deployed) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-5xl px-5 pb-28 pt-8 sm:px-6 sm:pb-14 sm:pt-12">
          <EmptyState
            icon={<IconShield className="h-6 w-6" />}
            title="Not deployed on this network"
            body="Switch to Robinhood Chain testnet where Sherwood is deployed."
          />
        </main>
      </>
    );
  }

  return (
    <>
      <Header />
      <main className="mx-auto max-w-5xl px-5 pb-28 pt-8 sm:px-6 sm:pb-14 sm:pt-12">
        <section className="rise">
          <Eyebrow>New protection</Eyebrow>
          <h1 className="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">
            Define the downside<span className="text-action">.</span>
          </h1>
          <p className="mt-2 text-sm text-mist">
            Hold it, protect it, keep the upside. Terms are priced live by the contract and never change after creation.
          </p>
        </section>

        {assets.length === 0 ? (
          <div className="mt-8">
            <EmptyState
              icon={<IconShield className="h-6 w-6" />}
              title="No registered assets"
              body="No stock tokens are registered on this chain yet."
            />
          </div>
        ) : (
          <div className="mt-8 grid grid-cols-1 gap-4 lg:grid-cols-5">
            {/* Ticket */}
            <div className="inset-card rise rounded-3xl p-6 lg:col-span-3" style={{ animationDelay: "60ms" }}>
              <Eyebrow>Asset</Eyebrow>
              <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-3">
                {assets.map((a, i) => {
                  const active = asset === a.token;
                  const disabled = !a.active;
                  return (
                    <button
                      key={a.token}
                      type="button"
                      disabled={disabled}
                      onClick={() => setAsset(a.token)}
                      className={`rounded-2xl border px-3 py-3 text-left transition-colors duration-150 disabled:opacity-40 ${
                        active
                          ? "border-action/60 bg-surface-3"
                          : "border-line bg-surface hover:border-mist/40 hover:bg-white/[0.03]"
                      }`}
                      style={{ transitionDelay: `${i * 10}ms` }}
                    >
                      <span className="block font-display text-sm font-bold">{a.symbol}</span>
                      <span className="tnum mt-0.5 block text-xs text-mist">
                        {disabled ? "inactive" : fmtPrice(a.price8)}
                      </span>
                      {a.balance !== undefined && a.balance > 0n && !disabled ? (
                        <span className="tnum mt-0.5 block text-[10px] text-fog">
                          you hold {fmtQty(a.balance, a.decimals)}
                        </span>
                      ) : null}
                    </button>
                  );
                })}
              </div>

              <div className="mt-6">
                <div className="flex items-baseline justify-between">
                  <Eyebrow>Amount ({selected?.symbol ?? "tokens"})</Eyebrow>
                  {selected && held !== undefined && held > 0n ? (
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
                  className="tnum mt-2 w-full rounded-xl border border-line bg-surface-2 px-4 py-3 text-sm outline-none focus:border-action/60"
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
                        ? `Position guard: you hold ${fmtQty(held, selected.decimals, selected.symbol)} — the contract rejects protecting more.`
                        : `You hold ${fmtQty(held, selected.decimals, selected.symbol)} — protection never leaves your wallet.`}
                  </p>
                ) : null}
              </div>

              <div className="mt-6">
                <Eyebrow>Protection level</Eyebrow>
                <div className="mt-2">
                  <SegmentedControl options={LEVELS} value={level} onChange={setLevel} />
                </div>
              </div>

              <div className="mt-6">
                <Eyebrow>Duration</Eyebrow>
                <div className="mt-2">
                  <SegmentedControl options={DURATIONS} value={duration} onChange={setDuration} />
                </div>
              </div>
            </div>

            {/* Terms rail */}
            <div className="lg:col-span-2">
              <div className="inset-card rise sticky rounded-3xl p-6 lg:top-24" style={{ animationDelay: "120ms" }}>
                <Eyebrow>Terms</Eyebrow>
                {quote ? (
                  <>
                    <div className="mt-4">
                      <div className="text-xs text-mist">Premium due now</div>
                      <div className="tnum mt-1 font-display text-4xl font-bold leading-none tracking-tight text-ink">
                        {fmtUsd18(premiumUSD18)}
                      </div>
                      <div className="tnum mt-1 text-xs text-mist">
                        {premiumToken.toLocaleString("en-US", { maximumFractionDigits: 2 })} {st?.symbol}
                      </div>
                    </div>
                    <dl className="mt-6 space-y-3 text-sm">
                      <Row label="Position value" value={fmtUsd18((amountWei * (selected?.price8 ?? 0n)) / 10n ** 8n)} />
                      <Row label="Entry price (live feed)" value={fmtPrice(selected?.price8)} />
                      <Row label="Your floor" value={fmtUsd18(protectedUSD18)} />
                      <Row label="Max payout" value={fmtUsd18(protectedUSD18)} />
                      <Row label="Expires" value={fmtExpiry(quote[2])} />
                    </dl>
                  </>
                ) : (
                  <p className="mt-4 text-sm text-mist">
                    Pick an asset and enter an amount — the contract quotes premium, floor, and expiry live.
                  </p>
                )}

                <div className="mt-6 space-y-3">
                  {needsApproval ? (
                    <button onClick={approve} disabled={!canApprove} className="btn-ghost w-full rounded-2xl px-4 py-3 text-sm">
                      Approve {st?.symbol ?? "token"}
                    </button>
                  ) : null}
                  <button onClick={create} disabled={!canCreate} className="btn-action w-full rounded-2xl px-4 py-3.5 text-sm">
                    {needsApproval ? "Approval required first" : overPosition ? "Exceeds your position" : "Buy Protection Note"}
                  </button>
                  <TxStatus state={txState} />
                </div>
              </div>
            </div>
          </div>
        )}
      </main>
    </>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <dt className="text-mist">{label}</dt>
      <dd className="tnum font-display font-bold">{value}</dd>
    </div>
  );
}
