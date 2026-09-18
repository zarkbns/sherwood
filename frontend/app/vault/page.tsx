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

  // Backer position: shares are the claim, the share price carries the premiums.
  const { data: shares } = useReadContract({
    address: deployed?.vault,
    abi: vaultAbi,
    functionName: "sharesOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!deployed },
  });
  const { data: totalShares } = useReadContract({
    address: deployed?.vault,
    abi: vaultAbi,
    functionName: "totalShares",
    query: { enabled: !!deployed },
  });
  const { data: feeBps } = useReadContract({
    address: deployed?.vault,
    abi: vaultAbi,
    functionName: "protocolFeeBps",
    query: { enabled: !!deployed },
  });

  const {
    writeContract: withdrawWrite,
    data: withdrawHash,
    isPending: isWithdrawing,
    error: withdrawError,
  } = useWriteContract();
  const withdrawReceipt = useWaitForTransactionReceipt({ hash: withdrawHash });

  const [withdrawAmount, setWithdrawAmount] = useState("");
  const withdrawWei = st ? parseTokenAmount(withdrawAmount, st.decimals) : 0n;

  function withdraw() {
    if (!deployed) return;
    withdrawWrite({ address: deployed.vault, abi: vaultAbi, functionName: "withdraw", args: [withdrawWei] });
  }

  // The claim is the shares' value at the current share price; what can actually leave
  // is the smaller of the claim and free capacity — reserved funds never move.
  const claim =
    shares !== undefined && totalShares !== undefined && totalShares > 0n && totalDeposits !== undefined
      ? (shares * totalDeposits) / totalShares
      : 0n;
  const withdrawable = claim > 0n && availableCapacity !== undefined && availableCapacity < claim ? availableCapacity : claim;
  const backerPct = feeBps !== undefined ? 100 - Number(feeBps) / 100 : null;

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

  const withdrawTxState: TxFail | null = isWithdrawing
    ? { kind: "pending", text: "Confirm in wallet…" }
    : withdrawReceipt.isLoading
      ? { kind: "busy", text: "Waiting for confirmation…" }
      : withdrawReceipt.isSuccess
        ? { kind: "success", text: "Confirmed." }
        : withdrawError
          ? { kind: "error", text: `Failed: ${withdrawError.message.slice(0, 120)}` }
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
            Every active protection is backed by money already set aside. The protocol never sells more protection
            than it can pay out — capacity is checked before a single premium is taken.
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
                  <Eyebrow>Vault in use</Eyebrow>
                  <div className="tnum mt-2 font-display text-5xl font-bold leading-none tracking-tight">
                    {(utilization * 100).toFixed(1)}
                    <span className="text-2xl text-mist">%</span>
                  </div>
                  <p className="mt-2 text-xs text-mist">
                    reserved collateral against deposits · {bufferPct !== null ? `${bufferPct}% buffer` : "buffer —"} held
                    back at all times
                  </p>
                </div>
                <div className="grid grid-cols-2 gap-x-8 gap-y-3 sm:grid-cols-3">
                  <div>
                    <div className="text-[11px] uppercase tracking-[0.12em] text-mist">In the vault</div>
                    <div className="tnum mt-0.5 font-display text-lg font-bold">{tok(totalDeposits, st)}</div>
                  </div>
                  <div>
                    <div className="text-[11px] uppercase tracking-[0.12em] text-mist">Locked (reserved)</div>
                    <div className="tnum mt-0.5 font-display text-lg font-bold">{tok(reserved, st)}</div>
                  </div>
                  <div>
                    <div className="text-[11px] uppercase tracking-[0.12em] text-mist">Free capacity</div>
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
                <Eyebrow>Back the pool</Eyebrow>
                <p className="mt-2 text-sm text-fog">
                  {backerPct !== null ? `${backerPct}% of every premium` : "Most of every premium"} flows to backers pro
                  rata — Sherwood keeps {feeBps !== undefined ? Number(feeBps) / 100 : "—"}%. Payouts are borne the same
                  way. Only the part of your stake that is not promised to an active note can ever be withdrawn.
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
                    {needsApproval ? "Approve first" : "Deposit"}
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
                  All of these are enforced on-chain and covered by the test suite, including a fuzzed
                  hold-over-sequence invariant.
                </p>
              </div>
            </div>

            {/* My stake */}
            {isConnected ? (
              <div className="inset-card rise mt-4 rounded-3xl p-6" style={{ animationDelay: "240ms" }}>
                <div className="flex flex-wrap items-end justify-between gap-4">
                  <div>
                    <Eyebrow>My stake</Eyebrow>
                    <div className="tnum mt-2 font-display text-4xl font-bold leading-none tracking-tight">
                      {tok(claim, st)}
                    </div>
                    <p className="mt-2 text-xs text-mist">
                      {tok(shares, st)} shares · share value carries the premiums already paid in and the payouts already
                      made
                    </p>
                  </div>
                  <div className="w-full max-w-xs">
                    <input
                      className="tnum w-full rounded-xl border border-line bg-surface-2 px-4 py-3 text-sm outline-none focus:border-action/60"
                      placeholder={`0.00 ${st?.symbol ?? ""}`}
                      value={withdrawAmount}
                      onChange={(e) => setWithdrawAmount(e.target.value)}
                      inputMode="decimal"
                    />
                    <div className="mt-2 flex items-center justify-between text-xs text-mist">
                      <span className="tnum">
                        withdrawable now {tok(withdrawable, st)} — the rest is locked by active notes or the buffer
                      </span>
                      {withdrawable > 0n ? (
                        <button
                          type="button"
                          onClick={() => setWithdrawAmount(formatUnits(withdrawable, st?.decimals ?? 6))}
                          className="shrink-0 text-action hover:underline"
                        >
                          Max
                        </button>
                      ) : null}
                    </div>
                    <button
                      onClick={withdraw}
                      disabled={!isConnected || withdrawWei === 0n || withdrawWei > withdrawable || isWithdrawing || withdrawReceipt.isLoading}
                      className="btn-ghost mt-4 w-full rounded-2xl px-4 py-3 text-sm"
                    >
                      Withdraw
                    </button>
                    <TxStatus state={withdrawTxState} />
                  </div>
                </div>
              </div>
            ) : null}
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
  "No withdrawal — backer or protocol — can take funds an active note needs",
];

function tok(value: bigint | undefined, st?: { decimals: number; symbol: string }): string {
  if (value === undefined) return "—";
  const decimals = st?.decimals ?? 6;
  const num = Number(formatUnits(value, decimals)).toLocaleString("en-US", { maximumFractionDigits: 2 });
  return st ? `${num} ${st.symbol}` : num;
}
