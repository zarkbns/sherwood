"use client";

import { useState } from "react";
import { useAccount, useChainId, useWriteContract, useWaitForTransactionReceipt, useReadContract, useBalance } from "wagmi";
import { formatUnits } from "viem";
import { Header } from "@/components/Header";
import { EmptyState, ProgressBar, Eyebrow, TxStatus, IconVault, IconCheck, type TxFail } from "@/components/ui";
import { useDeployed, useVaultStats, settlementTokenFor, parseTokenAmount } from "@/lib/protocol";
import { vaultAbi, erc20Abi } from "@/lib/abis";

export default function Vault() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { deployed } = useDeployed();
  const { totalDeposits, reserved, availableCapacity, bufferBps } = useVaultStats();
  const st = settlementTokenFor(chainId);

  const [amount, setAmount] = useState("");
  const amountWei = st ? parseTokenAmount(amount, st.decimals) : 0n;

  const { data: stBalance } = useBalance({
    address,
    token: st?.address,
    query: { enabled: !!address && !!st?.address },
  });

  const { data: allowance } = useReadContract({
    address: st?.address,
    abi: erc20Abi,
    functionName: "allowance",
    args: address && deployed ? [address, deployed.vault] : undefined,
    query: { enabled: !!address && !!deployed && !!st?.address },
  });

  const { writeContract, data: txHash, isPending: isWriting, error } = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash: txHash });

  function approve() {
    if (!st) return;
    writeContract({ address: st.address, abi: erc20Abi, functionName: "approve", args: [deployed!.vault, amountWei] });
  }

  function deposit() {
    if (!deployed) return;
    writeContract({ address: deployed.vault, abi: vaultAbi, functionName: "deposit", args: [amountWei] });
  }

  const needsApproval = amountWei > 0n && allowance !== undefined && allowance < amountWei;

  const utilization =
    totalDeposits !== undefined && reserved !== undefined && totalDeposits > 0n
      ? Number(reserved) / Number(totalDeposits)
      : 0;
  const bufferPct = bufferBps !== undefined ? Number(bufferBps) / 100 : null;

  const txState: TxFail | null = isWriting
    ? { kind: "pending", text: "Confirm in wallet…" }
    : receipt.isLoading
      ? { kind: "busy", text: "Waiting for confirmation…" }
      : receipt.isSuccess
        ? { kind: "success", text: "Confirmed." }
        : error
          ? { kind: "error", text: `Failed: ${error.message.slice(0, 120)}` }
          : null;

  return (
    <>
      <Header />
      <main className="mx-auto max-w-5xl px-5 pb-28 pt-8 sm:px-6 sm:pb-14 sm:pt-12">
        <section className="rise">
          <Eyebrow>Collateral</Eyebrow>
          <h1 className="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">
            The vault<span className="text-action">.</span>
          </h1>
          <p className="mt-2 text-sm text-mist">
            Every active note is backed by reserved collateral. The protocol never sells more protection than it can
            cover.
          </p>
        </section>

        {!deployed ? (
          <div className="mt-8">
            <EmptyState
              icon={<IconVault className="h-6 w-6" />}
              title="Not deployed on this network"
              body="Switch to Robinhood Chain testnet where Sherwood is deployed."
            />
          </div>
        ) : (
          <>
            {/* Utilization hero */}
            <section className="inset-card rise mt-8 rounded-3xl p-6 sm:p-8" style={{ animationDelay: "60ms" }}>
              <div className="flex flex-wrap items-end justify-between gap-4">
                <div>
                  <Eyebrow>Capacity utilization</Eyebrow>
                  <div className="tnum mt-2 font-display text-5xl font-bold leading-none tracking-tight">
                    {(utilization * 100).toFixed(1)}
                    <span className="text-2xl text-mist">%</span>
                  </div>
                  <p className="mt-2 text-xs text-mist">
                    reserved against deposits · {bufferPct !== null ? `${bufferPct}% buffer` : "buffer —"} held back at
                    all times
                  </p>
                </div>
                <div className="grid grid-cols-2 gap-x-8 gap-y-3 sm:grid-cols-3">
                  <div>
                    <div className="text-[11px] uppercase tracking-[0.12em] text-mist">Deposits</div>
                    <div className="tnum mt-0.5 font-display text-lg font-bold">{tok(totalDeposits, st)}</div>
                  </div>
                  <div>
                    <div className="text-[11px] uppercase tracking-[0.12em] text-mist">Reserved</div>
                    <div className="tnum mt-0.5 font-display text-lg font-bold">{tok(reserved, st)}</div>
                  </div>
                  <div>
                    <div className="text-[11px] uppercase tracking-[0.12em] text-mist">Capacity</div>
                    <div className="tnum mt-0.5 font-display text-lg font-bold">{tok(availableCapacity, st)}</div>
                  </div>
                </div>
              </div>
              <div className="mt-6">
                <ProgressBar pct={utilization} tone={utilization > 0.8 ? "action" : "mist"} />
              </div>
            </section>

            <div className="mt-6 grid grid-cols-1 gap-4 lg:grid-cols-2">
              {/* Deposit ticket */}
              <div className="inset-card rise rounded-3xl p-6" style={{ animationDelay: "120ms" }}>
                <Eyebrow>Deposit collateral</Eyebrow>
                <p className="mt-2 text-sm text-fog">
                  Collateral providers earn premiums. Deposits are held in {st?.symbol ?? "the settlement token"};
                  owner withdrawals are limited to unencumbered surplus.
                </p>
                <input
                  className="tnum mt-4 w-full rounded-xl border border-line bg-surface-2 px-4 py-3 text-sm outline-none focus:border-action/60"
                  placeholder={`0.00 ${st?.symbol ?? ""}`}
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  inputMode="decimal"
                />
                {stBalance ? (
                  <div className="mt-2 flex items-center justify-between text-xs text-mist">
                    <span className="tnum">
                      balance {Number(formatUnits(stBalance.value, stBalance.decimals)).toLocaleString("en-US", { maximumFractionDigits: 2 })} {st?.symbol}
                    </span>
                    <button
                      type="button"
                      onClick={() => setAmount(formatUnits(stBalance.value, stBalance.decimals))}
                      className="text-action hover:underline"
                    >
                      Max
                    </button>
                  </div>
                ) : null}
                <div className="mt-5 space-y-3">
                  {needsApproval ? (
                    <button
                      onClick={approve}
                      disabled={!isConnected || isWriting || receipt.isLoading}
                      className="btn-ghost w-full rounded-2xl px-4 py-3 text-sm"
                    >
                      Approve {st?.symbol ?? "token"}
                    </button>
                  ) : null}
                  <button
                    onClick={deposit}
                    disabled={!isConnected || amountWei === 0n || needsApproval || isWriting || receipt.isLoading}
                    className="btn-action w-full rounded-2xl px-4 py-3.5 text-sm"
                  >
                    {needsApproval ? "Approval required first" : "Deposit"}
                  </button>
                  <TxStatus state={txState} />
                </div>
              </div>

              {/* Solvency rules */}
              <div className="inset-card rise rounded-3xl p-6" style={{ animationDelay: "180ms" }}>
                <Eyebrow>Solvency, verifiable</Eyebrow>
                <ul className="mt-4 space-y-3 text-sm text-fog">
                  {RULES.map((r) => (
                    <li key={r} className="flex items-start gap-3">
                      <IconCheck className="mt-0.5 h-4 w-4 shrink-0 text-action" />
                      <span>{r}</span>
                    </li>
                  ))}
                </ul>
                <p className="mt-5 text-xs text-mist">
                  All four properties are enforced on-chain and covered by the test suite, including a fuzzed
                  hold-over-sequence invariant.
                </p>
              </div>
            </div>
          </>
        )}
      </main>
    </>
  );
}

const RULES = [
  "Capacity is checked before any premium is collected",
  "Reserved collateral covers every active note's maximum payout",
  "A 20% reserve buffer stays unencumbered at all times",
  "Payouts re-verify the vault's real token balance at settlement",
];

function tok(value: bigint | undefined, st?: { decimals: number; symbol: string }): string {
  if (value === undefined) return "—";
  const decimals = st?.decimals ?? 6;
  const num = Number(formatUnits(value, decimals)).toLocaleString("en-US", { maximumFractionDigits: 2 });
  return st ? `${num} ${st.symbol}` : num;
}
