"use client";

import { useAccount, useChainId, useWriteContract, useWaitForTransactionReceipt, useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import { Header } from "@/components/Header";
import {
  EmptyState,
  Skeleton,
  Pill,
  Eyebrow,
  TxStatus,
  IconFile,
  IconArrow,
  type TxFail,
} from "@/components/ui";
import { useDeployed, useNotes, useAssets, useSettlementReceipts, settlementTokenFor, type NoteView } from "@/lib/protocol";
import { noteAbi } from "@/lib/abis";
import { fmtPrice, fmtUsd18, fmtExpiry, fmtCountdown, fmtQty } from "@/lib/format";
import Link from "next/link";

export default function Notes() {
  const { address } = useAccount();
  const chainId = useChainId();
  const { deployed } = useDeployed();
  const { notes, isLoading } = useNotes();
  const { assets } = useAssets();
  const receipts = useSettlementReceipts();
  const st = settlementTokenFor(chainId);

  const mine = notes.filter((n) => address && n.owner.toLowerCase() === address.toLowerCase());
  const settledById = new Map(receipts.map((r) => [r.noteId.toString(), r]));

  return (
    <>
      <Header />
      <main className="mx-auto max-w-5xl px-5 pb-28 pt-8 sm:px-6 sm:pb-14 sm:pt-12">
        <section className="rise">
          <Eyebrow>Positions</Eyebrow>
          <h1 className="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">
            Your notes<span className="text-action">.</span>
          </h1>
          <p className="mt-2 text-sm text-mist">
            Protection positions and their on-chain settlement records — every price and payout is replayable from the
            chain.
          </p>
        </section>

        <div className="mt-8 space-y-2">
          {!deployed ? (
            <EmptyState
              icon={<IconFile className="h-6 w-6" />}
              title="Not deployed on this network"
              body="Switch to Robinhood Chain testnet where Sherwood is deployed."
            />
          ) : isLoading ? (
            <>
              <SkeletonRow />
              <SkeletonRow />
            </>
          ) : mine.length === 0 ? (
            <EmptyState
              icon={<IconFile className="h-6 w-6" />}
              title="No notes yet"
              body="Buy your first Protection Note: pick an asset you hold, a floor, and a duration. All upside stays yours."
              actionHref="/protect"
              actionLabel="Buy protection"
            />
          ) : (
            mine.map((n, i) => (
              <NoteCard
                key={n.id.toString()}
                note={n}
                symbol={assets.find((a) => a.token === n.asset)?.symbol ?? "?"}
                decimals={assets.find((a) => a.token === n.asset)?.decimals ?? 18}
                stDecimals={st?.decimals ?? 6}
                stSymbol={st?.symbol ?? ""}
                receipt={settledById.get(n.id.toString())}
                delay={i * 50}
              />
            ))
          )}
        </div>

        {deployed && mine.length > 0 ? (
          <div className="mt-8 text-center">
            <Link href="/protect" className="inline-flex items-center gap-1 text-xs text-action hover:underline">
              Add protection <IconArrow className="h-3.5 w-3.5" />
            </Link>
          </div>
        ) : null}
      </main>
    </>
  );
}

function NoteCard({
  note,
  symbol,
  decimals,
  stDecimals,
  stSymbol,
  receipt,
  delay,
}: {
  note: NoteView;
  symbol: string;
  decimals: number;
  stDecimals: number;
  stSymbol: string;
  receipt?: { settlementPrice: bigint; payoutToken: bigint; recipient: string };
  delay: number;
}) {
  const { deployed } = useDeployed();
  const { writeContract, data: txHash, isPending, error } = useWriteContract();
  const receipt_ = useWaitForTransactionReceipt({ hash: txHash });

  const { data: settlable } = useReadContracts({
    allowFailure: false,
    query: { enabled: !!deployed && note.status === 0 },
    contracts: [
      { address: deployed?.note, abi: noteAbi, functionName: "isSettlable", args: [note.id] } as const,
    ],
  });

  const canSettle = !!deployed && note.status === 0 && settlable?.[0] === true && !isPending && !receipt_.isLoading;

  function settle() {
    if (!deployed) return;
    writeContract({ address: deployed.note, abi: noteAbi, functionName: "settle", args: [note.id] });
  }

  const settled = note.status === 1;
  const ready = !settled && settlable?.[0] === true;
  const txState: TxFail | null = isPending
    ? { kind: "pending", text: "Confirm in wallet…" }
    : receipt_.isLoading
      ? { kind: "busy", text: "Waiting for confirmation…" }
      : receipt_.isSuccess
        ? { kind: "success", text: "Settled on-chain." }
        : error
          ? { kind: "error", text: `Failed: ${error.message.slice(0, 120)}` }
          : null;

  return (
    <div
      className="inset-card rise rounded-2xl px-5 py-4"
      style={{ animationDelay: `${delay}ms` }}
    >
      <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-3">
        <div className="flex min-w-0 items-center gap-3">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-surface-2 font-display text-xs font-bold text-fog">
            {symbol.slice(0, 2)}
          </span>
          <div className="min-w-0">
            <div className="truncate text-sm text-ink">
              <span className="font-display font-bold">
                {symbol} · {Number(note.level) / 1e16}%
              </span>
              <span className="tnum ml-2 text-xs text-mist">#{note.id.toString()}</span>
            </div>
            <div className="tnum mt-0.5 truncate text-xs text-mist">
              {fmtQty(note.amount, decimals)} · entry {fmtPrice(note.entryPrice)} · premium {fmtUsd18(note.premiumUSD18)}
            </div>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <div className="text-right">
            <div className="tnum text-sm text-ink">{fmtUsd18(note.protectedUSD18)} floor</div>
            <div className="tnum mt-0.5 text-xs text-mist">
              {settled ? "closed" : ready ? "claim open" : fmtCountdown(note.expiry)}
            </div>
          </div>
          <Pill tone={settled ? "done" : ready ? "ready" : "neutral"}>
            {settled ? "settled" : ready ? "ready" : "active"}
          </Pill>
          {!settled ? (
            <button onClick={settle} disabled={!canSettle} className="btn-action rounded-full px-4 py-2 text-xs">
              Settle
            </button>
          ) : null}
        </div>
      </div>

      {receipt ? (
        <div className="tnum mt-3 rounded-2xl border border-line bg-surface-2 px-4 py-3 text-xs text-fog">
          <span className="uppercase tracking-[0.08em] text-mist">Settlement record · </span>
          price {fmtPrice(receipt.settlementPrice)} · payout{" "}
          {Number(formatUnits(receipt.payoutToken, stDecimals)).toLocaleString("en-US", { maximumFractionDigits: 2 })}{" "}
          {stSymbol} · paid to {short(receipt.recipient)}
        </div>
      ) : null}
      <TxStatus state={txState} />
    </div>
  );
}

function short(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function SkeletonRow() {
  return (
    <div className="inset-card flex items-center justify-between rounded-2xl px-5 py-4">
      <div className="flex items-center gap-3">
        <Skeleton className="h-9 w-9 rounded-xl" />
        <div className="space-y-1.5">
          <Skeleton className="h-3.5 w-32" />
          <Skeleton className="h-3 w-44" />
        </div>
      </div>
      <div className="flex items-center gap-3">
        <Skeleton className="h-3.5 w-20" />
        <Skeleton className="h-6 w-16 rounded-full" />
      </div>
    </div>
  );
}
