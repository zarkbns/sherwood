"use client";

import { useEffect, useMemo, useState } from "react";
import { useAccount, useChainId, usePublicClient, useReadContracts } from "wagmi";
import { Address, formatUnits, parseUnits } from "viem";
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
  feed: Address;
  active: boolean;
  price8: bigint | undefined;
  priceUpdatedAt: bigint | undefined;
  balance: bigint | undefined;
  decimals: number;
};

/** Registered assets with live Chainlink price and the connected user's balance. */
export function useAssets(): { assets: AssetView[]; isLoading: boolean } {
  const { deployed } = useDeployed();
  const { address } = useAccount();
  const { data: tokenList, isLoading: loadingList } = useReadContracts({
    allowFailure: false,
    query: { enabled: !!deployed },
    contracts: [{ ...registryRef(deployed), functionName: "allAssets" }] as const,
  });

  const tokens: Address[] = (tokenList?.[0] as Address[]) ?? [];
  const meta = useReadContracts({
    allowFailure: false,
    query: { enabled: tokens.length > 0 },
    contracts: tokens.flatMap((t) => [
      { address: deployed?.registry, abi: registryAbi, functionName: "getAsset", args: [t] } as const,
      { address: t, abi: erc20Abi, functionName: "balanceOf", args: [address ?? "0x0"] } as const,
      { address: t, abi: erc20Abi, functionName: "decimals" } as const,
    ]),
  });

  const assets: AssetView[] = useMemo(() => {
    if (!tokens.length || !meta.data) return [];
    return tokens.map((token, i) => {
      const asset = meta.data[i * 3] as unknown as readonly [string, Address, bigint, boolean, boolean];
      const balance = meta.data[i * 3 + 1] as bigint;
      const decimals = meta.data[i * 3 + 2] as number;
      return {
        token,
        symbol: asset[0],
        feed: asset[1],
        active: asset[3],
        price8: undefined,
        priceUpdatedAt: undefined,
        balance: address ? balance : undefined,
        decimals,
      };
    });
  }, [tokens, meta.data, address]);

  // Prices read per-feed (Chainlink only, per spec) in a second batch.
  const prices = useReadContracts({
    allowFailure: false,
    query: { enabled: assets.length > 0 },
    contracts: assets.map((a) => ({ address: a.feed, abi: aggregatorAbi, functionName: "latestRoundData" })),
  });

  const withPrices = useMemo(
    () =>
      assets.map((a, i) => {
        const round = prices.data?.[i] as
          | readonly [bigint, bigint, bigint, bigint, bigint]
          | undefined;
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
