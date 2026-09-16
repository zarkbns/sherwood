# Sherwood — Build Spec

Complete technical specification. `AGENTS.md` is the build contract; this is the reference for all vault, capacity, and settlement logic. If code and spec disagree, fix the code.

---

## 1. Protocol Summary

Sherwood sells downside protection for tokenized stocks. A user holding a stock token buys a **Protection Note**: they pay a premium in a stablecoin and define a floor (70/80/90% of entry value). At expiry, the note settles against a Chainlink price. If price < floor, the Vault pays `floor − current`. The user keeps all upside.

**Deployed on Robinhood Chain only** (mainnet 4663, testnet 46630 — an Arbitrum-based L2). Settlement token is USDG; per-network config differs only in token and feed addresses.

---

## 2. Core Formulas

All USD math is internally **18 decimals** (USD-18). Prices arrive from Chainlink with 8 decimals; conversion happens at the boundary. **8 decimals is enforced, not assumed** — `AssetRegistry` rejects any feed whose `decimals()` is not 8, at registration and at rotation, so no note can ever be priced at a different scale.

```
valueUSD18        = amount18 × price8 / 1e8                      // current USD value of position
protectedUSD18    = amount18 × entryPrice8 × level18 / 1e18 / 1e8 // floor value
premiumUSD18      = valueUSD18 × rateBps / 10_000
rateBps           = baseBps + tierBps(level) + durationBps(duration)
tokenLiability    = protectedUSD18 → settlement-token decimals   // reserved at creation

// Settlement narrows the basis to the position the owner still holds:
eligibleAmount18  = min(amount18, stock.balanceOf(owner))        // read at settle, never stored
payoutUSD18       = max(0, protectedUSD18(eligible) − valueUSD18(eligible))
payoutToken       = payoutUSD18 → settlement-token decimals      // transferred at settlement
```

A note protects a **real position**, so the payout can only ever cover the share of it the owner still holds when the note settles. Sold stock is unprotected stock: the payout shrinks proportionally, and a fully deserted position pays nothing. The note still settles and the **full** `tokenLiability` is released in every case — eligibility may only ever reduce a payout, never strand a reserve. Premium and liability at creation are computed on the full `amount18` and are never recomputed.

Three bounds close the gaps an audit found around this basis:

- **Aggregate stacking cap** — `create` refuses a new note if the holder's stack of active note amounts on the asset (`activeProtected[owner][asset]`, decremented at settlement) would exceed their current stock balance. One position can no longer back N notes whose aggregate coverage exceeds the real exposure; each individually-reserved note was solvent while the *portfolio* was not.
- **Claim window** — a payout is collectible between `expiry` and `expiry + SETTLEMENT_WINDOW` (30 days, the longest term the rate table prices). Past the deadline the note still settles and the reserve still releases, but the payout is **forfeited** (`NoteSettled` carries settlementPrice 0); the forfeit path reads no price, so even a dead feed cannot block the release.
- **Bound settlement feed** — the feed (and staleness bound) a note was priced against is snapshotted at creation and `settle` reads that, never the registry's current entry. Feed rotation therefore only affects notes that do not exist yet.

**Precise limitation (documented, not fixed):** eligibility is a spot read at the settlement instant. It is proof of *holdings-at-settlement*, not of continuous ownership across the window — a buyer who sold and re-acquires the same amount before settling (rebuy, flash loan, any transfer) passes it and collects in full. Closing that would require custody or checkpointed holding, both rejected to keep the model cash-settled and non-custodial; the aggregate cap bounds the stack but not this.

Token-unit conversion: `tokenAmount = usd18 / 10^(18 − tokenDecimals)` (USDG = 6 dec → /1e12, verified via `decimals()` on-chain on both Robinhood networks; the contracts never assume a fixed value — they read `decimals()` from the settlement token).

Manual verification (80% level, 5 TSLA @ $100 entry, 7-day):
- protectedUSD18 = 5e18 × 100e8 × 0.8e18 / 1e18 / 1e8 = 400e18 ($400) ✓
- Price settles $60 → payout = max(0, 400 − 300) = $100 ✓
- Price settles $90 → payout = max(0, 400 − 450) = 0 ✓
- Price rises $120 → payout = 0, user keeps full upside ✓
- Premium: value 500e18 × (100 + 100 + 50)/10_000 = $12.50 ✓
- Owner sold down to 2 TSLA, settles $60 → eligible 2e18: floor 160 − current 120 = **$40** payout, and the full $400 reserve still releases ✓
- Owner sold all 5 TSLA, settles $60 → eligible 0: **$0** payout, the note still settles, the full $400 reserve releases ✓

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
- **Claim window:** `expiry + SETTLEMENT_WINDOW` = expiry + 30 days (the longest priced term) — payouts forfeited past it; the reserve still releases
- **Vault reserve buffer:** 2000 bps (20%) — configurable by owner, cap 5000 bps, not withdrawable while set (§4 `withdrawSurplus`), and a raise that would strand existing reserves is refused (§4 `setBufferBps`)
- **Oracle max staleness:** 72 h default (covers weekend equity-market closure) — configurable per registry entry, owner-capped at 7 days
- **Stock-token scale:** 18 decimals (`STOCK_TOKEN_DECIMALS`) — enforced at registration
- **Oracle sequencer grace period:** 3600 s default — owner-configurable, capped at 1 day (§4 `ProtectionOracle`)

---

## 3. Architecture

```
User ──> ProtectionNote (struct registry, noteId-keyed)
          │ create(): validate asset → position guard (caller holds the stock) →
          │           read entry price → consume noteId → vault.reserve(liability) →
          │           collect premium → record
          └ settle(): after expiry → oracle settlement price →
                      vault.settlePayout(note) → transfer payout or release
SherwoodVault: deposits, reserved collateral, capacity checks, payouts
AssetRegistry: token → {feed, staleness, active}, owner-gated, 8-decimal feeds only
ProtectionOracle: AggregatorV3 wrapper, L2 sequencer-uptime + freshness + sanity gates
ProtectionMath: pure payout/premium/conversion functions
```

**Flow order is an invariant**, in two directions:

- *Before money moves:* the position guard and the capacity check happen **before** any premium collection or collateral reservation, so a failed create (under-collateralised or a caller who doesn't hold the stock) moves no tokens. Any revert after reservation rolls back the whole transaction (atomic).
- *Before an external call:* state is written **before** the token interaction that could re-enter. The vault records `reserved`/`totalDeposits` before pulling a premium or sending a payout, and `ProtectionNote` consumes `noteId` before calling the vault. A settlement token with transfer hooks therefore never observes — nor acts on — a check its own transfer is about to invalidate. Pinned by `test/Reentrancy.t.sol`.

---

## 4. Contracts

### SherwoodVault.sol
Holds settlement token. Tracks `totalDeposits` (deposits + received premiums) and `reserved` (Σ active note liabilities, token units).

**Stated assumption:** the settlement token moves exactly `amount` on `transfer`/`transferFrom`. USDG satisfies this. A fee-on-transfer or rebasing token would let custody drift below `totalDeposits` and break invariant 4 — `script/Deploy.s.sol` screens for code presence and ≤ 18 decimals at deploy, but no deploy-time check can detect a transfer fee, so the settlement token is a deliberate trust boundary, not an arbitrary one.

- `deposit(amount)` — pull token, `totalDeposits += amount`
- `reserveFor(noteId, payer, premium, liability)` — **capacity check first**: `premium + liability ≤ availableCapacity()`. That is the plain `reserved + liability ≤ totalDeposits − buffer` precondition tightened by the premium itself, and it implies invariant 1 with room to spare. Then `totalDeposits += premium` and `reserved += liability`, and **only then** the premium is pulled from the payer (checks-effects-interactions). Called only by ProtectionNote.
- `settlePayout(noteId, recipient, liability, payout)` — `payout ≤ liability` and `payout ≤ balance` both re-checked, then `reserved −= liability` and `totalDeposits −= payout` **before** the transfer to `recipient`. Called only by ProtectionNote. (`payout ≤ liability` is guaranteed by the math: payout = floor − current ≤ floor = liability.)
- `availableCapacity()` view — `min(totalDeposits − buffer − reserved)` clamped at 0
- Owner: `setBufferBps` (a raise is refused with `BufferBreachesReserves` unless `reserved ≤ totalDeposits × (1 − newBuffer)` still holds — otherwise an admin call would strand collateral that was legitimately reserved under a smaller buffer; lowerings always pass), `setNoteContract` (**set-once**: the first binding after deploy is final — repointing mid-life would strand every active note's reserve behind the old contract's `onlyNote` gate, and upgrades are full-stack redeploys, matching the immutable settlement token), `withdrawSurplus(to, amount)` — capped at `availableCapacity()`, so it can take neither reserved collateral nor the reserve buffer. The cap is exactly what keeps invariant 1 true *after* a withdrawal (`amount ≤ D(1−b) − R ⟹ (D − amount)(1−b) ≥ R`). Winding a vault fully down is therefore a deliberate two-step: settle the notes, `setBufferBps(0)`, withdraw.

### ProtectionNote.sol (plain struct registry, not a token)
Note data struct: `owner, asset, amount18, entryPrice8, level18, expiry, premiumUSD18, protectedUSD18, liabilityToken, status`. `noteId` starts at 1 and increments; `notes(noteId)` is a public mapping. Terms immutable after creation.

**Notes are deliberately non-transferable.** Protection is priced for the buyer, so `settle()` always pays the recorded `owner`. This removes the entire ERC-721 surface (approvals, receiver hooks, transfer reentrancy) with no product loss — there is no secondary-market requirement in V1. If transferability ever becomes a real requirement, it is an explicit V2 decision, not an accident of the token standard.

- `create(asset, amount, level, duration)` — full flow above; validates: asset registered + active, amount > 0, supported level/duration, then the **two-half position guard**: the caller must hold `amount` of the asset token *and* their whole stack of active notes on that asset (`activeProtected[owner][asset]`, decremented at settlement) must stay inside that holding, else `InsufficientPosition` — one position cannot back a stack of notes whose aggregate coverage exceeds the real exposure. The feed and staleness bound the note was priced against are snapshotted per note (`noteFeeds`/`noteMaxStaleness`) for settlement. The stock is verified, never transferred or custodied — Sherwood protects a position, it doesn't take it. This keeps the product a real downside hedge for tokenized-equity holders, not a naked speculative bet. Settlement remains cash-settled on the price difference. The id is consumed (`nextId += 1`) *before* `vault.reserveFor`, so a re-entrant create claims the next id instead of overwriting the note in flight and stranding its reserve.
- `settle(noteId)` — permissionless, only when `block.timestamp ≥ expiry` and status ACTIVE. Marks SETTLED and captures the recipient *before* any external read (so a hook-bearing asset cannot re-enter the same id and draw its liability twice), then reads the settlement price from the **feed bound at creation** (`noteFeeds[noteId]`/`noteMaxStaleness[noteId]` — never the registry's current entry), computes the payout against `eligibleAmount = min(amount18, stock.balanceOf(owner))`, and pays the recorded owner, releasing the **full** `liabilityToken` through the vault. Payouts are only collectible until `expiry + SETTLEMENT_WINDOW`; past that the note still settles — reserve released, `NoteSettled` carrying settlementPrice 0 — but the payout is forfeited, and the forfeit path reads no price so a dead feed cannot block it. Eligibility and the window shrink the payout only — they never block the settlement, never mutate the note, and never leave a reserve stranded.
- `quote(asset, amount, level, duration)` — live on-chain quote (premium, floor, expiry) so the UI never recomputes rates or prices client-side.
- `calculatePayout(note, settlementPrice8)` — capped by the owner's current holding and by the claim window (zero past it), on the same basis as `settle()`, so the view can never promise more than settlement will pay.
- `isSettlable(noteId)` — derived view: exists + ACTIVE + past expiry.
- Status: `ACTIVE → SETTLED` (payout can be zero — deserted position or forfeited claim; a SETTLABLE state is derivable from expiry, not stored).

**Settle timing is bounded.** Originally settlement was open-ended — the price that settles a note was the first *accepted* price at any time after expiry, chosen by whoever called first. That decision was superseded by the audit: the safety argument covered only solvency (payout ≤ reserved liability, still true and still the hard bound), but the premium priced a bounded term while the exercise window was infinite, letting a 1-day note deliver an unbounded-horizon put. The claim window now bounds realized duration to the longest term the rate table prices (30 days). Within the window the original guarantee stands: the payout is the first accepted fresh price at or after expiry, and pinning to the expiry instant would require a price at a moment nobody is obliged to supply. Past the window the payout is forfeited and the reserve releases unconditionally — an unclaimed note never strands capacity.

### AssetRegistry.sol
- `registerAsset(token, symbol, feed, staleness)` — owner. Rejects a feed whose `decimals()` is not 8 with `UnsupportedFeedDecimals(feedDecimals)`: every `ProtectionMath` formula is written at 8 decimals, so a 6-decimal feed would under-price a position 100× and an 18-decimal feed over-price it 1e10× — silently, and against the buyer. Mirrors that check onto the token side with `UnsupportedTokenDecimals(tokenDecimals)`: `usdValue`/`protectedValue` silently assume 18-dec stock units, so a non-18-dec token would mis-price premium, floor and payout by 10^(d−18) (6-dec → the buyer pays dust for coverage that can never pay); a token that cannot answer `decimals()` at all is not registrable (fail-closed).
- `setAssetActive(token, bool)` — owner (disable = reject new notes; existing notes settle normally against their bound feed)
- `setAssetFeed(token, feed)` — owner; same 8-decimal gate. Affects only notes created after the rotation: live notes settle against the feed bound at their creation, never the registry's current entry.
- `getAsset(token)` view → struct; `isSupported(token)` view; `allAssets()` view

### ProtectionOracle.sol
- `getPrice(feed, staleness)` → (price8, updatedAt) via `latestRoundData()`; reverts on, in order: sequencer down or inside its grace window (below), `answeredInRound < roundId` (`StaleRound`), `answer ≤ 0` / `updatedAt == 0` / `updatedAt > block.timestamp` (`InvalidPrice` — a stamp ahead of the block clock is rejected here rather than left to underflow), `block.timestamp − updatedAt > staleness` (`StalePrice`).
- **L2 sequencer-uptime gate.** Robinhood Chain is an Arbitrum-based L2. During a sequencer outage a feed's `updatedAt` can still look fresh while the round carries a pre-outage price, and the staleness guard alone cannot tell those apart. When `sequencerUptimeFeed` is set, every `getPrice` first consults Chainlink's standard uptime aggregator (answer `0` = up, `1` = down; `startedAt` = when the sequencer came back):
  - `answer != 0` → `SequencerDown`. **Fails closed:** an unexpected or malformed answer is treated as down, because refusing to price is always the safe direction.
  - `startedAt == 0` or in the future → `InvalidSequencerFeed`.
  - restarted less than `sequencerGracePeriod` ago → `SequencerGracePeriodNotOver`. The post-outage backlog lands in a burst, so the first rounds after a restart are precisely when prices are least trustworthy.
- `sequencerUptimeFeed == address(0)` disables the gate — the correct state for a chain that publishes no feed (Robinhood Chain testnet 46630 today). Owner-settable both ways: `setSequencerUptimeFeed`, `setSequencerGracePeriod` (capped at 1 day by `GracePeriodTooLong`). The address is never hardcoded; `script/Deploy.s.sol` reads `SEQUENCER_UPTIME_FEED`.
- No cached prices, no fallbacks, no user input.

### ProtectionMath.sol (library, pure)
`usdValue`, `protectedValue`, `payout`, `premium`, `toTokenUnits`, `rateBps`. Every formula above lives here — nothing inline elsewhere. Also exports `PRICE_DECIMALS = 8`, the single definition the registry's feed check is built on.

### Minimal vendored interfaces (zero external deps)
`IERC20` and `IAggregatorV3`. Rationale: no submodules → `forge build` never depends on network (flaky connectivity).

---

## 5. Events & Errors

Events: `NoteCreated(noteId, owner, asset, amount, entryPrice, level, expiry, premium, protectedValue, liability)`, `NoteSettled(noteId, settlementPrice, payout, recipient)`, `Deposited depositor/amount`, `Withdrawn to/amount`, `CapacityReserved/Released noteId/liability`, `PayoutExecuted(noteId, to, amount)`, `AssetRegistered(token, feed)`, `AssetStatusChanged(token, active)`, `AssetFeedUpdated(token, feed)`, `BufferChanged(bps)`, `NoteContractSet(noteContract)`, `OwnershipTransferred(prev, next)`, `SequencerUptimeFeedSet(feed)`, `SequencerGracePeriodSet(seconds)`.

Custom errors: `UnsupportedAsset`, `AssetInactive`, `StalePrice`, `StaleRound`, `InvalidPrice`, `InsufficientCapacity`, `InsufficientVaultBalance`, `InsufficientPosition`, `NotExpired`, `AlreadySettled`, `InvalidLevel`, `InvalidDuration`, `InvalidAmount`, `InvalidDecimals`, `Unauthorized`, `InvalidOwner`, `TransferFailed`, `BufferTooHigh`, `BufferBreachesReserves`, `EncumberedFunds`, `PayoutExceedsLiability`, `NotNoteContract`, `NoteNotFound`, `AlreadyRegistered`, `NotRegistered`, `ZeroAddress`, `StalenessTooHigh`, `UnsupportedFeedDecimals`, `SequencerDown`, `SequencerGracePeriodNotOver`, `InvalidSequencerFeed`, `GracePeriodTooLong`.

Every state transition emits. Settlement always emits `NoteSettled` with the exact price and payout (auditable trail).

---

## 6. Invariants (checked in tests + reasoning)

1. `reserved ≤ totalDeposits − totalDeposits×buffer/10_000` at all times — including across an owner `withdrawSurplus` (capped at `availableCapacity()`) and an owner `setBufferBps` (a raise that would breach it is refused). Neither admin call can move this line.
2. Every ACTIVE note has `liabilityToken` fully counted in `reserved`, and every reserved wei belongs to exactly one note with a distinct id — no orphaned reserves.
3. `payout ≤ liabilityToken` for every settlement.
4. Vault balance ≥ `reserved` after any sequence of deposits/creates/settlements/withdrawals (premiums add real tokens).
5. Capacity is checked before any premium movement.
6. No user- or owner-supplied price ever reaches settlement math; only oracle-validated prices.
7. Note terms never mutate after creation; settle is the only transition and only after expiry.
8. Every note's creator held at least `amount` of the asset at creation (position guard). Enforced at `create`, not re-checked at `settle` — the buyer may sell after purchasing protection; the note still settles to them (an insurance claim, not a transfer).
9. When the chain publishes an L2 sequencer uptime feed, no price is used for entry or settlement while the sequencer is down or inside its restart grace window — and the gate fails closed on malformed uptime data.
10. Every registered feed reports 8 decimals — the scale every price formula assumes — checked at registration *and* at rotation.
11. Reserve/deposit accounting and the `noteId` counter are written before any external token call, so a transfer-hooked settlement token cannot re-enter past a capacity check or claim a note id twice.

---

## 7. Chain Configuration

`script/Config.s.sol` maps chainId → config. Sherwood targets **Robinhood Chain only**; facts below verified against docs.robinhood.com/chain (September 2026).

| Network | chainId | Settlement token | Feeds |
|---|---|---|---|
| Robinhood Chain mainnet | 4663 | USDG `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` (canonical, per docs) | Chainlink tokenized-equity feeds per stock token — read addresses from docs.chain.link at deploy, never hardcode. Same rule for the L2 sequencer uptime feed (`SEQUENCER_UPTIME_FEED`) |
| Robinhood Chain testnet | 46630 | MockUSDG `0x8c4aa106a0A0d9ECAeD5C87e1AE766aa8Efbf006` — "Mock USDG", 6 dec, public `faucet()` of 1,000 per address per 24h (verified live 2026-09-13) | feed availability unconfirmed on testnet; if absent, register demo feeds and disclose. No uptime feed is published on 46630, so the sequencer gate ships disabled there |

**Settlement token resolution** (`DeployConfig`): `SETTLEMENT_TOKEN` wins when set, otherwise the chain default above; an unset pair reverts `NoSettlementToken`. `settlementToken(chainId, override)` reverts `MockTokenOnMainnet` if the testnet mock is ever paired with 4663 — the mock's admin can mint without limit, so reserving real collateral against it would misstate what backs a note. `script/Deploy.s.sol` additionally refuses a token with no code, or with more than 18 decimals, before deploying anything. The canonical testnet USDG at `0x7E955252E15c84f5768B83c41a71F9eba181802F` stays the intended production-equivalent token and is a one-line env switch once Robinhood's testnet drip actually reaches wallet addresses; Sherwood's flows have never received it. MockUSDG was chosen because premiums, vault reserves and payouts must be exercisable on testnet to be verifiable at all. `script/Faucet.s.sol` claims it (testnet-only).

**Oracle env** (`script/Deploy.s.sol`): `SEQUENCER_UPTIME_FEED` (optional — unset means the gate is off, and the deploy log says so out loud) and `SEQUENCER_GRACE_PERIOD` (default 3600 s). Both are read back from chain after deploy and the script fails if they did not land.

Oracle facts: feeds use standard `AggregatorV3.latestRoundData()`; USD feeds are 8 decimals (now enforced by the registry); updates run 24/5 with **no heartbeats off-hours** — so `maxStaleness` per asset (default 72h, owner-capped at 7 days) is the primary guard, and outage-frozen prices are rejected naturally.

**L2 sequencer uptime: no feed exists on Robinhood Chain (verified 2026-09-14).** Four independent checks agree:

1. Chainlink's L2 Sequencer Uptime Feeds page lists 11 networks (Arbitrum One, Base, Celo, Mantle, MegaETH, Metis, OP, Scroll, Soneium, X Layer, zkSync) and states Chainlink *"is no longer expanding L2 Sequencer Uptime Feeds to additional networks"*. Robinhood Chain is not among them.
2. Chainlink's own address-book data for this chain — `reference-data-directory.vercel.app/feeds-robinhood-mainnet.json`, 57 feeds — contains no `sequencer` or `uptime` string in any field of any record.
3. Robinhood's Oracles & Price Feeds page *mandates* the check (`require(sequencerStatus == 0)` plus a grace period on `startedAt`) but publishes no address to satisfy it.
4. Robinhood's protocol-contracts page lists no oracle or pause contract; `oraclePaused()` reverts on both a stock token and a feed proxy, so there is no chain-native substitute.

Consequence, stated plainly: the gate is correct code with no feed to point at, so it ships off on both networks and **`maxStaleness` is Sherwood's only price-freshness protection here**. The marginal loss is small for this protocol specifically — equity feeds are 24/5 with no off-hours heartbeats, so a legitimately closed-market price and an outage-frozen price are already indistinguishable inside the 72 h bound, and an uptime feed would only have caught outages *shorter* than that bound. A sequencer outage also stops L2 block production outright on this Orbit rollup, so nothing can be read or written during it; the real residual exposure is the restart burst, which the grace window would have covered had a feed existed.

**Mainnet feed addresses (proxy = the `AggregatorV3` entry point), read live from `rpc.mainnet.chain.robinhood.com` on 2026-09-14, chainId 4663 confirmed, all `decimals() == 8`:**

| Asset | Feed proxy | `description()` |
|---|---|---|
| TSLA | `0x4A1166a659A55625345e9515b32adECea5547C38` | RHTSLA / USD |
| AMZN | `0xD5a1508ceD74c084eBf3cBe853e2C968fB2a651C` | Robinhood AMZN / USD |
| PLTR | `0x820ABedFF239034956B7A9d2F0a331f9F075eB4c` | Robinhood PLTR / USD |
| AMD | `0x943A29E7ae51A4798823ca9eEd2ed533B2A22C72` | RHAMD / USD |
| NFLX | **none — not published on this chain** | — |

A mainnet launch therefore cannot support NFLX today despite it being in the initial asset list: the chain publishes 35 equity feeds (AAPL AMD AMZN ASML BABA CLSK COIN CRCL CRWV DELL EWY GME GOOGL INTC IONQ META MSFT MSTR MU NBIS NVDA ORCL PLTR QQQ RGTI RKLB SGOV SLV SNDK SPCX SPY TSLA TSM USAR USO) and NFLX is not one of them. Drop it or substitute from that list at mainnet deploy; do not register a placeholder.

**Stock token addresses** are registered per network in AssetRegistry at deploy via `TOKEN_<SYMBOL>` / `FEED_<SYMBOL>` env — the protocol is asset-agnostic; whatever tokenized-stock contracts exist on the chain get registered with their feed.

Verification sequence: `forge build` → `forge test` (100%) → deploy to Robinhood Chain testnet → record addresses in `deploy/deployments.json`.

---

## 8. Frontend

Next.js App Router + wagmi/viem + Tailwind v4 with the DESIGN.md midnight theme (`#000814` canvas, `#010d1e` surfaces, weight-100 body, single `#1c6cff` action color, 24px cards, inset shadows only).

Pages: **Dashboard** (holdings + active notes + vault stats), **Protect** (create-note flow with live quote: premium, floor, max payout, expiry), **Notes** (list + settle button when expired + settlement receipts), **Vault** (collateral, reserved, capacity utilization).

All reads/writes go through wagmi hooks to deployed addresses; no price data outside Chainlink-onchain. The app runs on Robinhood Chain testnet (single-chain; chain defined in `frontend/lib/chain.ts`, id 46630).
