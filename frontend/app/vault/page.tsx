"use client";

import { useState } from "react";
import { useAccount, useChainId, useWriteContract, useWaitForTransactionReceipt, useReadContract } from "wagmi";
import { Header } from "@/components/Header";
import { Empty, StatCard, TxStatus } from "@/components/ui";
import { useDeployed, useVaultStats, settlementTokenFor, parseTokenAmount } from "@/lib/protocol";
import { vaultAbi, erc20Abi } from "@/lib/abis";
import { formatUnits } from "viem";

export default function Vault() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { deployed } = useDeployed();
  const { totalDeposits, reserved, availableCapacity, bufferBps } = useVaultStats();
  const st = settlementTokenFor(chainId);

  const [amount, setAmount] = useState("");
  const amountWei = st ? parseTokenAmount(amount, st.decimals) : 0n;

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
      ? ((Number(reserved) * 100) / Number(totalDeposits)).toFixed(1)
      : "—";

  const state = isWriting
    ? "Confirm in wallet…"
    : receipt.isLoading
      ? "Waiting for confirmation…"
      : receipt.isSuccess
        ? "Confirmed."
        : error
          ? `Failed: ${error.message.slice(0, 120)}`
          : null;

  return (
    <>
      <Header />
      <main className="mx-auto max-w-5xl px-6 py-10">
        <h1 className="font-display text-4xl font-bold tracking-tight">
          Vault<span className="text-action">.</span>
        </h1>
        <p className="mt-2 text-sm text-mist">
          Every active note is backed by reserved collateral. The protocol never sells more protection than it can cover.
        </p>

        {!deployed ? (
          <div className="mt-8">
            <Empty title="Not deployed on this network" body="Switch to Robinhood Chain testnet where Sherwood is deployed." />
          </div>
        ) : (
          <>
            <div className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <StatCard label="Total deposits" value={tok(totalDeposits, st)} />
              <StatCard label="Reserved" value={tok(reserved, st)} sub="backing active notes" />
              <StatCard label="Available capacity" value={tok(availableCapacity, st)} />
              <StatCard
                label="Utilization"
                value={`${utilization}%`}
                sub={`reserve buffer ${bufferBps !== undefined ? Number(bufferBps) / 100 : "—"}%`}
              />
            </div>

            <div className="mt-10 grid grid-cols-1 gap-4 lg:grid-cols-2">
              <div className="inset-card rounded-3xl p-6">
                <div className="text-xs uppercase tracking-widest text-mist">Deposit collateral</div>
                <p className="mt-2 text-sm text-fog">
                  Collateral providers earn premiums. Deposits are held in {st?.symbol ?? "the settlement token"}; owner
                  withdrawals are limited to unencumbered surplus.
                </p>
                <input
                  className="mt-4 w-full rounded-xl border border-line bg-surface-2 px-4 py-3 text-sm outline-none"
                  placeholder={`0.00 ${st?.symbol ?? ""}`}
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  inputMode="decimal"
                />
                <div className="mt-4 space-y-3">
                  {needsApproval ? (
                    <button
                      onClick={approve}
                      disabled={!isConnected || isWriting || receipt.isLoading}
                      className="btn-action w-full rounded-xl px-4 py-3 text-sm"
                    >
                      Approve {st?.symbol ?? "token"}
                    </button>
                  ) : null}
                  <button
                    onClick={deposit}
                    disabled={!isConnected || amountWei === 0n || needsApproval || isWriting || receipt.isLoading}
                    className="btn-action w-full rounded-xl px-4 py-3 text-sm"
                  >
                    {needsApproval ? "Approval required first" : "Deposit"}
                  </button>
                  <TxStatus state={state} />
                </div>
              </div>

              <div className="inset-card rounded-3xl p-6">
                <div className="text-xs uppercase tracking-widest text-mist">Solvency, verifiable</div>
                <ul className="mt-3 space-y-2 text-sm text-fog">
                  <li>· Capacity is checked before any premium is collected</li>
                  <li>· Reserved collateral covers every active note&apos;s maximum payout</li>
                  <li>· A {bufferBps !== undefined ? Number(bufferBps) / 100 : 20}% buffer stays unencumbered at all times</li>
                  <li>· Payouts re-verify the vault&apos;s real token balance at settlement</li>
                </ul>
              </div>
            </div>
          </>
        )}
      </main>
    </>
  );
}

function tok(value: bigint | undefined, st?: { decimals: number; symbol: string }): string {
  if (value === undefined) return "—";
  const decimals = st?.decimals ?? 6;
  const num = Number(formatUnits(value, decimals)).toLocaleString("en-US", { maximumFractionDigits: 2 });
  return st ? `${num} ${st.symbol}` : num;
}
