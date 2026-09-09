# Sherwood — Build Spec

Complete technical specification. `AGENTS.md` is the build contract; this is the reference for all vault, capacity, and settlement logic. If code and spec disagree, fix the code.

---

## 1. Protocol Summary

Sherwood sells downside protection for tokenized stocks. A user holding a stock token buys a **Protection Note**: they pay a premium in a stablecoin and define a floor (70/80/90% of entry value). At expiry, the note settles against a Chainlink price. If price < floor, the Vault pays `floor − current`. The user keeps all upside.

**Deployed on two chains:** Robinhood Chain testnet and Arbitrum One/Sepolia. Identical bytecode; per-chain config differs only in settlement token and feed addresses.

---

## 2. Core Formulas

All USD math is internally **18 decimals** (USD-18). Prices arrive from Chainlink with 8 decimals; conversion happens at the boundary.

```
valueUSD18        = amount18 × price8 / 1e8                      // current USD value of position
protectedUSD18    = amount18 × entryPrice8 × level18 / 1e18 / 1e8 // floor value
payoutUSD18       = max(0, protectedUSD18 − valueUSD18)
premiumUSD18      = valueUSD18 × rateBps / 10_000
rateBps           = baseBps + tierBps(level) + durationBps(duration)
tokenLiability    = protectedUSD18 → settlement-token decimals   // reserved at creation
payoutToken       = payoutUSD18 → settlement-token decimals      // transferred at settlement
```

Token-unit conversion: `tokenAmount = usd18 / 10^(18 − tokenDecimals)` (USDC = 6 dec → /1e12; USDG = 18 dec → /1).

Manual verification (80% level, 5 TSLA @ $100 entry, 7-day):
- protectedUSD18 = 5e18 × 100e8 × 0.8e18 / 1e18 / 1e8 = 400e18 ($400) ✓
- Price settles $60 → payout = max(0, 400 − 300) = $100 ✓
- Price settles $90 → payout = max(0, 400 − 450) = 0 ✓
- Price rises $120 → payout = 0, user keeps full upside ✓
- Premium: value 500e18 × (100 + 100 + 50)/10_000 = $12.50 ✓

### Premium rate table (V1, protocol-defined, transparent)

| Component | Value |
|---|---|
| Base | 100 bps (1.0%) |
| Tier 70% | +100 bps |
| Tier 80% | +100 bps |
| Tier 90% | +200 bps |
| Duration 7d | +50 bps |
| Duration 14d | +75 bps |
| Duration 30d | +100 bps |

### Fixed terms

- **Levels:** 70, 80, 90 (% × 1e16 as level18)
- **Durations:** 7, 14, 30 days
- **Vault reserve buffer:** 2000 bps (20%) — configurable by owner, cap 5000 bps
- **Oracle max staleness:** 72 h default (covers weekend equity-market closure) — configurable per registry entry, owner-capped at 7 days

---

## 3. Architecture

```
User ──> ProtectionNote (ERC721)
          │ create(): validate asset → read entry price →
          │           vault.reserve(liability) → collect premium → mint
          └ settle(): after expiry → oracle settlement price →
                      vault.settlePayout(note) → transfer payout or release
SherwoodVault: deposits, reserved collateral, capacity checks, payouts
AssetRegistry: token → {feed, staleness, active}
ProtectionOracle: AggregatorV3 wrapper, freshness + sanity validation
ProtectionMath: pure payout/premium/conversion functions
```

**Flow order is an invariant:** capacity check and collateral reservation happen **before** premium collection. Any revert after reservation rolls back the whole transaction (atomic).

---

## 4. Contracts

### SherwoodVault.sol
Holds settlement token. Tracks `totalDeposits` (deposits + received premiums) and `reserved` (Σ active note liabilities, token units).

- `deposit(amount)` — pull token, `totalDeposits += amount`
- `reserveFor(payer, premium, liability)` — **capacity check first**: `reserved + liability ≤ totalDeposits − buffer`; then pull premium from payer (`totalDeposits += premium`), `reserved += liability`. Called only by ProtectionNote.
- `settlePayout(recipient, liability, payout)` — transfer `payout` to recipient, `reserved −= liability`. Called only by ProtectionNote. `payout ≤ liability` must hold (math guarantees: payout = floor − current ≤ floor = liability).
- `availableCapacity()` view — `min(totalDeposits − buffer − reserved)` clamped at 0
- Owner: `setBufferBps`, `setPendingNote`/authorization of the note contract

### ProtectionNote.sol (ERC721)
Note data struct: `asset, amount18, entryPrice8, level18, expiry, premiumUSD18, protectedUSD18, liabilityToken, status`. tokenId = noteId, minted to buyer. Terms immutable after creation.

- `create(asset, amount, level, duration)` — full flow above; validates: asset active, amount > 0, supported level/duration, caller holds enough stock token? (No — protection doesn't require holding the token; it pays out on price delta. Keep it a cash-settled instrument.)
- `settle(noteId)` — permissionless, only when `block.timestamp ≥ expiry` and status ACTIVE. Reads settlement price, computes payout, calls vault, sets SETTLED.
- `calculatePayout(note, settlementPrice8)` — pure, spec formula.
- Status: `ACTIVE → SETTLED` (payout can be zero; a SETTLABLE state is derivable from expiry, not stored).

### AssetRegistry.sol
- `registerAsset(token, symbol, feed, staleness)` — owner
- `setAssetActive(token, bool)` — owner (disable = reject new notes; existing notes settle normally)
- `getAsset(token)` view → struct; `isSupported(token)` view

### ProtectionOracle.sol
- `getPrice(feed)` → (price8, updatedAt) via `latestRoundData()`; reverts on: `answeredInRound < roundId`, `answer ≤ 0`, `updatedAt == 0`, `block.timestamp − updatedAt > staleness`.
- No cached prices, no fallbacks, no user input.

### ProtectionMath.sol (library, pure)
`usdValue`, `protectedValue`, `payout`, `premium`, `toTokenUnits`, `rateBps`. Every formula above lives here — nothing inline elsewhere.

### Minimal vendored interfaces (zero external deps)
`IERC20`, `IERC721Receiver`, `IAggregatorV3`, and a lean self-contained `ERC721` (ownerOf/balanceOf/approve/setApprovalForAll/transferFrom/safeTransferFrom, events, no enumeration/metadata). Rationale: no submodules → `forge build` never depends on network (flaky connectivity).

---

## 5. Events & Errors

Events: `NoteCreated(noteId, owner, asset, amount, entryPrice, level, expiry, premium, protectedValue, liability)`, `NoteSettled(noteId, settlementPrice, payout, recipient)`, `Deposited depositor/amount`, `CapacityReserved/Released noteId/liability`, `PayoutExecuted(noteId, to, amount)`, `AssetRegistered(token, feed)`, `AssetStatusChanged(token, active)`, `BufferChanged(bps)`.

Custom errors: `UnsupportedAsset`, `AssetInactive`, `StalePrice`, `InvalidPrice`, `InsufficientCapacity`, `InsufficientVaultBalance`, `NotExpired`, `AlreadySettled`, `InvalidLevel`, `InvalidDuration`, `InvalidAmount`, `Unauthorized`, `TransferFailed`, `BufferTooHigh`.

Every state transition emits. Settlement always emits `NoteSettled` with the exact price and payout (auditable trail).

---

## 6. Invariants (checked in tests + reasoning)

1. `reserved ≤ totalDeposits − totalDeposits×buffer/10_000` at all times.
2. Every ACTIVE note has `liabilityToken` fully counted in `reserved`.
3. `payout ≤ liabilityToken` for every settlement.
4. Vault balance ≥ `reserved` after any sequence of deposits/creates/settlements (premiums add real tokens).
5. Capacity is checked before any premium movement.
6. No user- or owner-supplied price ever reaches settlement math; only oracle-validated prices.
7. Note terms never mutate after creation; settle is the only transition and only after expiry.

---

## 7. Chain Configuration

`script/Config.s.sol` maps chainId → config; `RPC_URL`/env overrides for unknown chains (e.g. Robinhood testnet chain ID to be confirmed at first deploy).

| Chain | chainId | Settlement token | Feeds |
|---|---|---|---|
| Arbitrum One | 42161 | USDC (0xaf88…) 6 dec | Chainlink equity feeds (TSLA/AMZN/NFLX/PLTR/AMD) — verify addresses at deploy |
| Arbitrum Sepolia | 421614 | test USDC (faucet.circle.com) | mock feeds if real ones absent |
| Robinhood Chain testnet | TBD (read from RPC) | USDG (TBD — verify official address) | TBD — verify available feeds; if absent, register mock feed for demo only and disclose |

**Stock token addresses** are registered per chain in AssetRegistry at deploy — the protocol is asset-agnostic; whatever tokenized-stock contracts exist on the chain (or demo ERC20s on testnet) get registered with their feed.

Verification sequence: `forge build` (no warnings) → `forge test` (100%) → deploy both chains → record addresses in `deploy/deployments.json`.

---

## 8. Frontend

Next.js App Router + wagmi/viem + Tailwind v4 with the DESIGN.md midnight theme (`#000814` canvas, `#010d1e` surfaces, weight-100 body, single `#1c6cff` action color, 24px cards, inset shadows only).

Pages: **Dashboard** (holdings + active notes + vault stats), **Protect** (create-note flow with live quote: premium, floor, max payout, expiry), **Notes** (list + settle button when expired + settlement receipts), **Vault** (collateral, reserved, capacity utilization).

All reads/writes go through wagmi hooks to deployed addresses; no price data outside Chainlink-onchain. Chain switcher covers Arbitrum One / Arbitrum Sepolia / Robinhood testnet.
