# Sherwood — Build Spec

Complete technical specification. `AGENTS.md` is the build contract; this is the reference for all vault, capacity, and settlement logic. If code and spec disagree, fix the code.

---

## 1. Protocol Summary

Sherwood sells downside protection for tokenized stocks. A user holding a stock token buys a **Protection Note**: they pay a premium in a stablecoin and define a floor (70/80/90% of entry value). At expiry, the note settles against a Chainlink price. If price < floor, the Vault pays `floor − current`. The user keeps all upside.

**Deployed on Robinhood Chain only** (mainnet 4663, testnet 46630 — an Arbitrum-based L2). Settlement token is USDG; per-network config differs only in token and feed addresses.

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

Token-unit conversion: `tokenAmount = usd18 / 10^(18 − tokenDecimals)` (USDG = 6 dec → /1e12, verified via `decimals()` on-chain on both Robinhood networks; the contracts never assume a fixed value — they read `decimals()` from the settlement token).

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
| Duration 1d | +25 bps |
| Duration 7d | +50 bps |
| Duration 14d | +75 bps |
| Duration 30d | +100 bps |

### Fixed terms

- **Levels:** 70, 80, 90 (% × 1e16 as level18)
- **Durations:** 1, 7, 14, 30 days
- **Vault reserve buffer:** 2000 bps (20%) — configurable by owner, cap 5000 bps
- **Oracle max staleness:** 72 h default (covers weekend equity-market closure) — configurable per registry entry, owner-capped at 7 days

---

## 3. Architecture

```
User ──> ProtectionNote (struct registry, noteId-keyed)
          │ create(): validate asset → position guard (caller holds the stock) →
          │           read entry price → vault.reserve(liability) → collect premium → record
          └ settle(): after expiry → oracle settlement price →
                      vault.settlePayout(note) → transfer payout or release
SherwoodVault: deposits, reserved collateral, capacity checks, payouts
AssetRegistry: token → {feed, staleness, active}, owner-gated
ProtectionOracle: AggregatorV3 wrapper, freshness + sanity validation
ProtectionMath: pure payout/premium/conversion functions
```

**Flow order is an invariant:** the position guard and capacity check happen **before** any premium collection or collateral reservation, so a failed create (under-collateralised or a caller who doesn't hold the stock) moves no tokens. Any revert after reservation rolls back the whole transaction (atomic).

---

## 4. Contracts

### SherwoodVault.sol
Holds settlement token. Tracks `totalDeposits` (deposits + received premiums) and `reserved` (Σ active note liabilities, token units).

- `deposit(amount)` — pull token, `totalDeposits += amount`
- `reserveFor(payer, premium, liability)` — **capacity check first**: `reserved + liability ≤ totalDeposits − buffer`; then pull premium from payer (`totalDeposits += premium`), `reserved += liability`. Called only by ProtectionNote.
- `settlePayout(recipient, liability, payout)` — transfer `payout` to recipient, `reserved −= liability`. Called only by ProtectionNote. `payout ≤ liability` must hold (math guarantees: payout = floor − current ≤ floor = liability).
- `availableCapacity()` view — `min(totalDeposits − buffer − reserved)` clamped at 0
- Owner: `setBufferBps`, `setNoteContract` (authorization of the note contract), `withdrawSurplus` (unencumbered funds only)

### ProtectionNote.sol (plain struct registry, not a token)
Note data struct: `owner, asset, amount18, entryPrice8, level18, expiry, premiumUSD18, protectedUSD18, liabilityToken, status`. `noteId` starts at 1 and increments; `notes(noteId)` is a public mapping. Terms immutable after creation.

**Notes are deliberately non-transferable.** Protection is priced for the buyer, so `settle()` always pays the recorded `owner`. This removes the entire ERC-721 surface (approvals, receiver hooks, transfer reentrancy) with no product loss — there is no secondary-market requirement in V1. If transferability ever becomes a real requirement, it is an explicit V2 decision, not an accident of the token standard.

- `create(asset, amount, level, duration)` — full flow above; validates: asset registered + active, amount > 0, supported level/duration, then **position guard: caller must hold `amount` of the asset token** (`balanceOf(msg.sender) ≥ amount`, else `InsufficientPosition`). The stock is verified, never transferred or custodied — Sherwood protects a position, it doesn't take it. This keeps the product a real downside hedge for tokenized-equity holders, not a naked speculative bet. Settlement remains cash-settled on the price difference.
- `settle(noteId)` — permissionless, only when `block.timestamp ≥ expiry` and status ACTIVE. Reads settlement price, computes payout, pays the recorded owner via the vault, sets SETTLED.
- `quote(asset, amount, level, duration)` — live on-chain quote (premium, floor, expiry) so the UI never recomputes rates or prices client-side.
- `calculatePayout(note, settlementPrice8)` — pure, spec formula.
- `isSettlable(noteId)` — derived view: exists + ACTIVE + past expiry.
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
`IERC20` and `IAggregatorV3`. Rationale: no submodules → `forge build` never depends on network (flaky connectivity).

---

## 5. Events & Errors

Events: `NoteCreated(noteId, owner, asset, amount, entryPrice, level, expiry, premium, protectedValue, liability)`, `NoteSettled(noteId, settlementPrice, payout, recipient)`, `Deposited depositor/amount`, `CapacityReserved/Released noteId/liability`, `PayoutExecuted(noteId, to, amount)`, `AssetRegistered(token, feed)`, `AssetStatusChanged(token, active)`, `BufferChanged(bps)`.

Custom errors: `UnsupportedAsset`, `AssetInactive`, `StalePrice`, `InvalidPrice`, `InsufficientCapacity`, `InsufficientVaultBalance`, `InsufficientPosition`, `NotExpired`, `AlreadySettled`, `InvalidLevel`, `InvalidDuration`, `InvalidAmount`, `Unauthorized`, `TransferFailed`, `BufferTooHigh`.

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
8. Every note's creator held at least `amount` of the asset at creation (position guard). Enforced at `create`, not re-checked at `settle` — the buyer may sell after purchasing protection; the note still settles to them (an insurance claim, not a transfer).

---

## 7. Chain Configuration

`script/Config.s.sol` maps chainId → config. Sherwood targets **Robinhood Chain only**; facts below verified against docs.robinhood.com/chain (September 2026).

| Network | chainId | Settlement token | Feeds |
|---|---|---|---|
| Robinhood Chain mainnet | 4663 | USDG `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` (canonical, per docs) | Chainlink tokenized-equity feeds per stock token — read addresses from docs.chain.link at deploy, never hardcode |
| Robinhood Chain testnet | 46630 | MockUSDG `0x8c4aa106a0A0d9ECAeD5C87e1AE766aa8Efbf006` — "Mock USDG", 6 dec, public `faucet()` of 1,000 per address per 24h (verified live 2026-09-13) | feed availability unconfirmed on testnet; if absent, register demo feeds and disclose |

**Settlement token resolution** (`DeployConfig`): `SETTLEMENT_TOKEN` wins when set, otherwise the chain default above; an unset pair reverts `NoSettlementToken`. `settlementToken(chainId, override)` reverts `MockTokenOnMainnet` if the testnet mock is ever paired with 4663 — the mock's admin can mint without limit, so reserving real collateral against it would misstate what backs a note. `script/Deploy.s.sol` additionally refuses a token with no code, or with more than 18 decimals, before deploying anything. The canonical testnet USDG at `0x7E955252E15c84f5768B83c41a71F9eba181802F` stays the intended production-equivalent token and is a one-line env switch once Robinhood's testnet drip actually reaches wallet addresses; Sherwood's flows have never received it. MockUSDG was chosen because premiums, vault reserves and payouts must be exercisable on testnet to be verifiable at all. `script/Faucet.s.sol` claims it (testnet-only).

Oracle facts: feeds use standard `AggregatorV3.latestRoundData()`; USD feeds are 8 decimals; updates run 24/5 with **no heartbeats off-hours** — so `maxStaleness` per asset (default 72h, owner-capped at 7 days) is the primary guard, and outage-frozen prices are rejected naturally. Robinhood docs also recommend an L2 sequencer-uptime check before trusting prices; that integration is a known V2 item, covered today by the staleness guard.

**Stock token addresses** are registered per network in AssetRegistry at deploy via `TOKEN_<SYMBOL>` / `FEED_<SYMBOL>` env — the protocol is asset-agnostic; whatever tokenized-stock contracts exist on the chain get registered with their feed.

Verification sequence: `forge build` → `forge test` (100%) → deploy to Robinhood Chain testnet → record addresses in `deploy/deployments.json`.

---

## 8. Frontend

Next.js App Router + wagmi/viem + Tailwind v4 with the DESIGN.md midnight theme (`#000814` canvas, `#010d1e` surfaces, weight-100 body, single `#1c6cff` action color, 24px cards, inset shadows only).

Pages: **Dashboard** (holdings + active notes + vault stats), **Protect** (create-note flow with live quote: premium, floor, max payout, expiry), **Notes** (list + settle button when expired + settlement receipts), **Vault** (collateral, reserved, capacity utilization).

All reads/writes go through wagmi hooks to deployed addresses; no price data outside Chainlink-onchain. The app runs on Robinhood Chain testnet (single-chain; chain defined in `frontend/lib/chain.ts`, id 46630).
