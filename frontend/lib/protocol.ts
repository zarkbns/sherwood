"use client";

import { useEffect, useMemo, useState } from "react";
import { useAccount, useChainId, usePublicClient, useReadContracts } from "wagmi";
import { Address, formatUnits, parseUnits, zeroAddress } from "viem";
import { getLogs } from "viem/actions";
import { addressesFor, SETTLEMENT_TOKEN, ProtocolAddresses } from "./addresses";
import { noteAbi, noteSettledEvent, vaultAbi, registryAbi, aggregatorAbi, erc20Abi } from "./abis";

export type NoteView = {
  id: bigint;
  owner: Address;
  asset: Address;
  amount: bigint;
  entryPrice: bigint;
  level: bigint;
  expiry: bigint;
  premiumUSD18: bigint;
  protectedUSD18: bigint;
  liabilityToken: bigint;
  status: number; // 0 ACTIVE, 1 SETTLED
};

export function useDeployed(): { deployed: ProtocolAddresses | null; chainId: number } {
  const chainId = useChainId();
  const deployed = addressesFor(chainId);
  return { deployed, chainId };
}

export function useVaultStats() {
  const { deployed } = useDeployed();
  const { data, isLoading } = useReadContracts({
    allowFailure: false,
    query: { enabled: !!deployed },
    contracts: [
      { ...vaultRef(deployed), functionName: "totalDeposits" },
      { ...vaultRef(deployed), functionName: "reserved" },
      { ...vaultRef(deployed), functionName: "availableCapacity" },
      { ...vaultRef(deployed), functionName: "bufferBps" },
    ] as const,
  });

  return {
    totalDeposits: data?.[0],
    reserved: data?.[1],
    availableCapacity: data?.[2],
    bufferBps: data?.[3],
    isLoading,
  };
}

function vaultRef(deployed: ProtocolAddresses | null) {
  return { address: deployed?.vault, abi: vaultAbi };
}

function noteRef(deployed: ProtocolAddresses | null) {
  return { address: deployed?.note, abi: noteAbi };
}

export type AssetView = {
  token: Address;
  symbol: string;
  /** ERC20 `name()` — undefined when the token does not expose it. */
  name: string | undefined;
  feed: Address;
  active: boolean;
  /** Per-asset staleness bound from the registry, in seconds. */
  maxStaleness: bigint;
  price8: bigint | undefined;
  priceUpdatedAt: bigint | undefined;
  /** undefined = not connected or the read failed; distinct from a genuine 0. */
  balance: bigint | undefined;
  /** Falls back to 18 (the protocol's only supported stock scale) if `decimals()` fails. */
  decimals: number;
};

/**
 * Every asset the registry lists, with its live Chainlink price, staleness bound and the
 * connected holder's balance. Reads are allowFailure by design: one misbehaving token
 * (missing `name`, a reverted `balanceOf`) must degrade that one row, not blank the whole
 * list — a batch that throws on first failure turns a single bad registration into an app
 * that looks empty.
 */
export function useAssets(): { assets: AssetView[]; isLoading: boolean } {
  const { deployed } = useDeployed();
  const { address } = useAccount();
  const { data: tokenList, isLoading: loadingList } = useReadContracts({
    allowFailure: false,
    query: { enabled: !!deployed },
    contracts: [{ ...registryRef(deployed), functionName: "allAssets" }] as const,
  });

  const tokens: Address[] = (tokenList?.[0] as Address[]) ?? [];
  const PER_TOKEN = 4;
  const meta = useReadContracts({
    allowFailure: true,
    query: { enabled: tokens.length > 0 },
    contracts: tokens.flatMap((t) => [
      { address: deployed?.registry, abi: registryAbi, functionName: "getAsset", args: [t] } as const,
      { address: t, abi: erc20Abi, functionName: "balanceOf", args: [address ?? zeroAddress] } as const,
      { address: t, abi: erc20Abi, functionName: "decimals" } as const,
      { address: t, abi: erc20Abi, functionName: "name" } as const,
    ]),
  });

  const assets: AssetView[] = useMemo(() => {
    if (!tokens.length || !meta.data) return [];
    const rows: AssetView[] = [];
    tokens.forEach((token, i) => {
      const [assetRes, balanceRes, decimalsRes, nameRes] = meta.data!.slice(i * PER_TOKEN, (i + 1) * PER_TOKEN);
      // No registry entry means the row has nothing honest to display; drop it.
      if (!assetRes || assetRes.status === "failure") return;
      const asset = assetRes.result as unknown as readonly [string, Address, bigint, boolean, boolean];
      rows.push({
        token,
        symbol: asset[0],
        name: nameRes?.status === "success" ? (nameRes.result as string) : undefined,
        feed: asset[1],
        active: asset[3],
        maxStaleness: asset[2],
        price8: undefined,
        priceUpdatedAt: undefined,
        balance: address && balanceRes?.status === "success" ? (balanceRes.result as bigint) : undefined,
        decimals: decimalsRes?.status === "success" ? Number(decimalsRes.result) : 18,
      });
    });
    return rows;
  }, [tokens, meta.data, address]);

  // Prices read per-feed (Chainlink only, per spec) in a second batch.
  const prices = useReadContracts({
    allowFailure: true,
    query: { enabled: assets.length > 0 },
    contracts: assets.map((a) => ({ address: a.feed, abi: aggregatorAbi, functionName: "latestRoundData" })),
  });

  const withPrices = useMemo(
    () =>
      assets.map((a, i) => {
        const roundRes = prices.data?.[i];
        const round = roundRes?.status === "success" ? (roundRes.result as readonly [bigint, bigint, bigint, bigint, bigint]) : undefined;
        return { ...a, price8: round ? round[1] : undefined, priceUpdatedAt: round ? round[3] : undefined };
      }),
    [assets, prices.data]
  );

  return { assets: withPrices, isLoading: loadingList };
}

function registryRef(deployed: ProtocolAddresses | null) {
  return { address: deployed?.registry, abi: registryAbi };
}

/** All notes on-chain (looped over nextId), with owner resolution. */
export function useNotes(): { notes: NoteView[]; isLoading: boolean } {
  const { deployed } = useDeployed();
  const { data: nextId, isLoading } = useReadContracts({
    allowFailure: false,
    query: { enabled: !!deployed },
    contracts: [{ ...noteRef(deployed), functionName: "nextId" }] as const,
  });

  const count = nextId ? Number(nextId[0]) : 0;
  const ids = useMemo(() => Array.from({ length: count }, (_, i) => BigInt(i + 1)), [count]);

  const { data, isLoading: loadingNotes } = useReadContracts({
    allowFailure: false,
    query: { enabled: ids.length > 0 },
    contracts: ids.map((id) => ({ address: deployed?.note, abi: noteAbi, functionName: "notes", args: [id] }) as const),
  });

  const notes: NoteView[] = useMemo(() => {
    if (!data || !ids.length) return [];
    return ids.map((id, i) => {
      const n = data[i] as unknown as readonly [
        Address,
        Address,
        bigint,
        bigint,
        bigint,
        bigint,
        bigint,
        bigint,
        bigint,
        number,
      ];
      return {
        id,
        owner: n[0],
        asset: n[1],
        amount: n[2],
        entryPrice: n[3],
        level: n[4],
        expiry: n[5],
        premiumUSD18: n[6],
        protectedUSD18: n[7],
        liabilityToken: n[8],
        status: Number(n[9]),
      };
    });
  }, [data, ids]);

  return { notes, isLoading: isLoading || loadingNotes };
}

export type SettlementReceipt = { noteId: bigint; settlementPrice: bigint; payoutToken: bigint; recipient: Address };

/** Settlement receipts pulled from NoteSettled logs — the auditable on-chain record. */
export function useSettlementReceipts(): SettlementReceipt[] {
  const { deployed } = useDeployed();
  const client = usePublicClient();
  const [receipts, setReceipts] = useState<SettlementReceipt[]>([]);

  useEffect(() => {
    if (!deployed || !client) return;
    let cancelled = false;
    (async () => {
      const logs = await getLogs(client, {
        address: deployed.note,
        event: noteSettledEvent,
        fromBlock: "earliest",
        toBlock: "latest",
      });
      if (cancelled) return;
      setReceipts(
        logs.map((l) => ({
          noteId: l.args.noteId as bigint,
          settlementPrice: l.args.settlementPrice as bigint,
          payoutToken: l.args.payoutToken as bigint,
          recipient: l.args.recipient as Address,
        }))
      );
    })().catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [deployed, client]);

  return receipts;
}

export function settlementTokenFor(chainId: number) {
  return SETTLEMENT_TOKEN[chainId];
}

/** premiumUSD18 -> settlement token units (the vault applies the same truncation). */
export function usd18ToToken(usd18: bigint, tokenDecimals: number): bigint {
  if (tokenDecimals >= 18) return usd18 / 10n ** BigInt(tokenDecimals - 18);
  return usd18 / 10n ** BigInt(18 - tokenDecimals);
}

export function parseTokenAmount(value: string, decimals: number): bigint {
  if (!value) return 0n;
  try {
    return parseUnits(value, decimals);
  } catch {
    return 0n;
  }
}
