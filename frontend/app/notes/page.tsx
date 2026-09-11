"use client";

import { useState } from "react";
import { useAccount, useChainId, useWriteContract, useWaitForTransactionReceipt, useReadContracts } from "wagmi";
import { Header } from "@/components/Header";
import { Empty, TxStatus } from "@/components/ui";
import { useDeployed, useNotes, useAssets, useSettlementReceipts, settlementTokenFor } from "@/lib/protocol";
import { noteAbi } from "@/lib/abis";
import { fmtPrice, fmtUsd18, fmtExpiry, isExpired } from "@/lib/format";
import { formatUnits } from "viem";

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
      <main className="mx-auto max-w-5xl px-6 py-10">
        <h1 className="font-display text-4xl font-bold tracking-tight">
          Notes<span className="text-action">.</span>
        </h1>
        <p className="mt-2 text-sm text-mist">Your protection positions and their on-chain settlement records.</p>

        <div className="mt-8 space-y-3">
          {!deployed ? (
            <Empty title="Not deployed on this network" body="Switch to Robinhood Chain testnet where Sherwood is deployed." />
          ) : isLoading ? (
            <Empty title="Loading…" body="Reading notes from the chain." />
          ) : mine.length === 0 ? (
            <Empty title="No notes yet" body="Buy your first Protection Note from the Protect page." />
          ) : (
            mine.map((n) => (
              <NoteCard
                key={n.id.toString()}
                note={n}
                symbol={assets.find((a) => a.token === n.asset)?.symbol ?? "?"}
                stDecimals={st?.decimals ?? 6}
                stSymbol={st?.symbol ?? ""}
                receipt={settledById.get(n.id.toString())}
              />
            ))
          )}
        </div>
      </main>
    </>
  );
}

function NoteCard({
  note,
  symbol,
  stDecimals,
  stSymbol,
  receipt,
}: {
  note: Awaited<ReturnType<typeof useNotes>>["notes"][number];
  symbol: string;
  stDecimals: number;
  stSymbol: string;
  receipt?: { settlementPrice: bigint; payoutToken: bigint; recipient: string };
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

  const expired = isExpired(note.expiry);
  const state = isPending
    ? "Confirm in wallet…"
    : receipt_.isLoading
      ? "Waiting for confirmation…"
      : receipt_.isSuccess
        ? "Settled."
        : error
          ? `Failed: ${error.message.slice(0, 120)}`
          : null;

  return (
    <div className="inset-card rounded-3xl p-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <div className="font-display text-lg font-bold">
            #{note.id.toString()} · {symbol} · {Number(note.level) / 1e16}% floor
          </div>
          <div className="mt-1 text-xs text-mist">
            entry {fmtPrice(note.entryPrice)} · {fmtUsd18(note.protectedUSD18)} protected · premium{" "}
            {fmtUsd18(note.premiumUSD18)} · expires {fmtExpiry(note.expiry)}
          </div>
        </div>
        <div className="flex items-center gap-3">
          <span
            className={`rounded-full border px-3 py-1 text-xs ${
              note.status === 1 ? "border-line text-mist" : expired ? "border-action text-action" : "border-line text-fog"
            }`}
          >
            {note.status === 1 ? "settled" : expired ? "ready to settle" : "active"}
          </span>
          {note.status === 0 ? (
            <button onClick={settle} disabled={!canSettle} className="btn-action rounded-xl px-4 py-2 text-sm">
              Settle
            </button>
          ) : null}
        </div>
      </div>

      {receipt ? (
        <div className="mt-4 rounded-2xl border border-line bg-surface-2 p-4 text-xs text-fog">
          <span className="text-mist">Settlement record:</span> price {fmtPrice(receipt.settlementPrice)} · payout{" "}
          {Number(formatUnits(receipt.payoutToken, stDecimals)).toFixed(2)} {stSymbol} · paid to {short(receipt.recipient)}
        </div>
      ) : null}
      <TxStatus state={state} />
    </div>
  );
}

function short(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}
