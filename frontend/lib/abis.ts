/**
 * Hand-trimmed ABIs: only the functions the UI calls, matching src/*.sol exactly.
 * Kept in-repo instead of generated so the build never needs codegen tooling.
 */

/** NoteSettled as a standalone event — used for typed log filtering (getLogs event form). */
export const noteSettledEvent = {
  type: "event",
  name: "NoteSettled",
  inputs: [
    { name: "noteId", type: "uint256", indexed: true },
    { name: "settlementPrice", type: "uint256", indexed: false },
    { name: "payoutToken", type: "uint256", indexed: false },
    { name: "recipient", type: "address", indexed: true },
  ],
} as const;

export const noteAbi = [
  {
    name: "create",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "level", type: "uint256" },
      { name: "duration", type: "uint256" },
    ],
    outputs: [{ name: "noteId", type: "uint256" }],
  },
  {
    name: "settle",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "noteId", type: "uint256" }],
    outputs: [],
  },
  {
    name: "quote",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "level", type: "uint256" },
      { name: "duration", type: "uint256" },
    ],
    outputs: [
      { name: "premiumUSD18", type: "uint256" },
      { name: "protectedUSD18", type: "uint256" },
      { name: "expiry", type: "uint256" },
    ],
  },
  {
    name: "calculatePayout",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "noteId", type: "uint256" },
      { name: "settlementPrice8", type: "uint256" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "isSettlable",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "noteId", type: "uint256" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "nextId",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "notes",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "", type: "uint256" }],
    outputs: [
      { name: "owner", type: "address" },
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "entryPrice", type: "uint256" },
      { name: "level", type: "uint256" },
      { name: "expiry", type: "uint256" },
      { name: "premiumUSD18", type: "uint256" },
      { name: "protectedUSD18", type: "uint256" },
      { name: "liabilityToken", type: "uint256" },
      { name: "status", type: "uint8" },
    ],
  },
  {
    type: "event",
    name: "NoteCreated",
    inputs: [
      { name: "noteId", type: "uint256", indexed: true },
      { name: "owner", type: "address", indexed: true },
      { name: "asset", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "entryPrice", type: "uint256", indexed: false },
      { name: "level", type: "uint256", indexed: false },
      { name: "expiry", type: "uint256", indexed: false },
      { name: "premiumUSD18", type: "uint256", indexed: false },
      { name: "protectedUSD18", type: "uint256", indexed: false },
      { name: "liabilityToken", type: "uint256", indexed: false },
    ],
  },
  noteSettledEvent,
] as const;

export const vaultAbi = [
  {
    name: "deposit",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    name: "totalDeposits",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "reserved",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "availableCapacity",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "bufferBps",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "token",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
] as const;

export const registryAbi = [
  {
    name: "isSupported",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "token", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "getAsset",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "token", type: "address" }],
    outputs: [
      { name: "symbol", type: "string" },
      { name: "feed", type: "address" },
      { name: "maxStaleness", type: "uint256" },
      { name: "active", type: "bool" },
      { name: "registered", type: "bool" },
    ],
  },
  {
    name: "allAssets",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address[]" }],
  },
] as const;

export const aggregatorAbi = [
  {
    name: "latestRoundData",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "roundId", type: "uint80" },
      { name: "answer", type: "int256" },
      { name: "startedAt", type: "uint256" },
      { name: "updatedAt", type: "uint256" },
      { name: "answeredInRound", type: "uint80" },
    ],
  },
] as const;

export const erc20Abi = [
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "decimals",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    name: "symbol",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;
