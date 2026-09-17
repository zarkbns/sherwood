"use client";

import { useState } from "react";
import { useAccount, useChainId, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { formatUnits } from "viem";
import { SegmentedControl, Eyebrow, TxStatus, type TxFail } from "@/components/ui";
import { TokenLogo } from "@/components/TokenLogo";
import { useDeployed, useAssets, settlementTokenFor, parseTokenAmount, usd18ToToken } from "@/lib/protocol";
import { noteAbi, erc20Abi } from "@/lib/abis";
import { fmtUsd18, fmtPrice, fmtExpiry, fmtQty } from "@/lib/format";

/**
 * The buy-protection flow, in one place.
 *
 * Both the dashboard panel and /protect render this, so the quote read, the position
 * guard, the approval step and the create call exist exactly once. Two copies of a
 * transaction flow is how one page silently drifts from the other's safety checks.
 *
 * `variant` only changes the arrangement, never the behaviour:
 *   "card"  — the dashboard panel: From/To blocks, fee row, one CTA (the reference layout)
 *   "page"  — the full /protect view: asset grid, ticket, sticky terms rail
 */

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

export function ProtectFlow({ variant = "page" }: { variant?: "page" | "card" }) {
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

  // Position guard mirrored from the contract: create() reverts InsufficientPosition unless
  // the caller holds the protected amount. Block it in the UI; don't mint reverts.
  const held = selected?.balance;
  const holdsEnough = held === undefined || held >= amountWei;
  const overPosition = amountWei > 0n && held !== undefined && held < amountWei;

  // The quote is read from the chain — the UI never prices anything itself.
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
    writeContract({ address: st.address, abi: erc20Abi, functionName: "approve", args: [deployed.vault, premiumToken] });
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
        ? { kind: "success", text: "Protection created — see your notes" }
        : failReason
          ? { kind: "error", text: `Failed: ${failReason}` }
          : null;

  const positionValue = (amountWei * (selected?.price8 ?? 0n)) / 10n ** 8n;

  const actions = (
    <div className="space-y-3">
      {needsApproval ? (
        <button onClick={approve} disabled={!canApprove} className="btn-ghost w-full rounded-2xl px-4 py-3 text-sm">
          Approve {st?.symbol ?? "token"}
        </button>
      ) : null}
      <button onClick={create} disabled={!canCreate} className="btn-action w-full rounded-2xl px-4 py-3.5 text-sm">
        {needsApproval ? "Approve first" : overPosition ? "More than you hold" : "Buy protection"}
      </button>
      <TxStatus state={txState} />
    </div>
  );

  /* ------------------------------------------------------------------ card variant —
   * The dashboard panel: From (your position) → To (your floor) → fee → CTA. */
  if (variant === "card") {
    return (
      <div className="flex h-full flex-col">
        <div className="flex items-baseline justify-between">
          <Eyebrow>Protect a position</Eyebrow>
          {selected && held !== undefined && held > 0n ? (
            <button
              type="button"
              onClick={() => setAmount(formatUnits(held, selected.decimals))}
              className="text-xs text-action hover:underline"
            >
              Max
            </button>
          ) : null}
        </div>

        {/* From */}
        <div className="mt-3 rounded-2xl bg-surface-3 p-4">
          <div className="text-[11px] uppercase tracking-[0.14em] text-mist">From · the stock you hold</div>
          <div className="mt-2 flex items-center justify-between gap-3">
            <input
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              inputMode="decimal"
              placeholder="0.00"
              className="tnum w-full min-w-0 bg-transparent font-display text-3xl font-bold tracking-tight outline-none placeholder:text-mist/50"
            />
            <div className="flex shrink-0 items-center gap-2 rounded-full bg-surface-2 px-3 py-2">
              {selected ? <TokenLogo symbol={selected.symbol} className="h-5 w-5" /> : null}
              <select
                value={asset}
                onChange={(e) => setAsset(e.target.value)}
                aria-label="Asset to protect"
                className="cursor-pointer appearance-none bg-transparent pr-1 text-sm text-ink outline-none"
              >
                <option value="">Select</option>
                {assets.map((a) => (
                  <option key={a.token} value={a.token} disabled={!a.active}>
                    {a.symbol}
                    {a.active ? "" : " (coming soon)"}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <div className="mt-2 flex items-center justify-between text-xs text-mist">
            <span className="tnum">{selected && amountWei > 0n ? fmtUsd18(positionValue) : "—"}</span>
            <span className="tnum">
              {held === undefined
                ? "connect to see balance"
                : `Balance: ${fmtQty(held, selected?.decimals ?? 18)}`}
            </span>
          </div>
        </div>

        <div className="relative -my-2 text-center">
          <span className="relative z-10 inline-block rounded-full border-4 border-surface bg-surface-2 px-2 py-1 text-xs text-mist">
            ↓
          </span>
        </div>

        {/* To */}
        <div className="rounded-2xl bg-surface-3 p-4">
          <div className="text-[11px] uppercase tracking-[0.14em] text-mist">To · your floor</div>
          <div className="tnum mt-2 font-display text-3xl font-bold tracking-tight">
            {protectedUSD18 !== undefined ? fmtUsd18(protectedUSD18) : "—"}
          </div>
          <div className="mt-3">
            <SegmentedControl options={LEVELS} value={level} onChange={setLevel} />
          </div>
          <div className="mt-2 flex items-center justify-between text-xs text-mist">
            <span>{quote ? `expires ${fmtExpiry(quote[2])}` : "pick an amount to quote"}</span>
            <span className="tnum">{selected ? fmtPrice(selected.price8) : "—"} now</span>
          </div>
        </div>

        <div className="mt-4">
          <Eyebrow>Duration</Eyebrow>
          <div className="mt-2">
            <SegmentedControl options={DURATIONS} value={duration} onChange={setDuration} />
          </div>
        </div>

        <div className="mt-4 flex items-center justify-between gap-3 text-xs text-mist">
          <span>
            ⓘ Paid up front and not refundable — the vault keeps the cost whether or not the price ever drops.
          </span>
          <span className="tnum shrink-0 rounded-xl bg-surface-3 px-3 py-1.5 text-ink">
            {premiumUSD18 !== undefined ? `${fmtUsd18(premiumUSD18)} cost` : "cost —"}
          </span>
        </div>

        {overPosition && selected ? (
          <p className="mt-3 text-xs text-loss">
            You hold {fmtQty(held, selected.decimals, selected.symbol)} — you can&apos;t protect more than you own.
          </p>
        ) : null}

        <div className="mt-auto pt-5">{actions}</div>
      </div>
    );
  }

  /* ------------------------------------------------------------------ page variant */
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-5">
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
                  active ? "border-action/60 bg-surface-3" : "border-line bg-surface hover:border-mist/40 hover:bg-white/[0.03]"
                }`}
                style={{ transitionDelay: `${i * 10}ms` }}
              >
                <span className="flex items-center gap-2">
                  <TokenLogo symbol={a.symbol} className="h-6 w-6" />
                  <span className="block font-display text-sm font-bold">{a.symbol}</span>
                </span>
                <span className="tnum mt-0.5 block text-xs text-mist">
                  {disabled ? "coming soon" : fmtPrice(a.price8)}
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
                ? "Connect a wallet to see what you hold."
                : overPosition
                  ? `You hold ${fmtQty(held, selected.decimals, selected.symbol)} — you can't protect more than you own.`
                  : `You hold ${fmtQty(held, selected.decimals, selected.symbol)}. The stock stays in your wallet.`}
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
                <div className="text-xs text-mist">Cost up front</div>
                <div className="tnum mt-1 font-display text-4xl font-bold leading-none tracking-tight text-ink">
                  {fmtUsd18(premiumUSD18)}
                </div>
                <div className="tnum mt-1 text-xs text-mist">
                  {premiumToken.toLocaleString("en-US", { maximumFractionDigits: 2 })} {st?.symbol}
                </div>
              </div>
              <dl className="mt-6 space-y-3 text-sm">
                <Row label="What you're protecting" value={fmtUsd18(positionValue)} />
                <Row label="Price now (from the chain)" value={fmtPrice(selected?.price8)} />
                <Row label="Your floor" value={fmtUsd18(protectedUSD18)} />
                <Row label="Most you can receive" value={fmtUsd18(protectedUSD18)} />
                <Row label="Expires" value={fmtExpiry(quote[2])} />
              </dl>
            </>
          ) : (
            <p className="mt-4 text-sm text-mist">
              Pick a stock and an amount — the cost, your floor and the expiry all come back from the chain.
            </p>
          )}

          <div className="mt-6">{actions}</div>
        </div>
      </div>
    </div>
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
