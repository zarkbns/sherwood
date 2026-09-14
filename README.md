# Sherwood 🛡️

> Programmable downside protection for tokenized stocks on Robinhood Chain.

Sherwood lets users protect their stock positions against downside risk while keeping all their upside. Buy a Protection Note, define your floor, and settle with verified prices. The web app is **SherwoodNotes**.

*Built for the Arbitrum Open House Singapore: Online Buildathon — deployed on Robinhood Chain testnet (chain ID 46630).*

---

## The Problem

Stock Tokens make equities programmable on-chain. But holding one still exposes you to market downside without native, straightforward protection.

Options are complex: you need to understand strikes, expiration, Greeks, and manage multiple positions. Centralized derivatives platforms take fees, have custody risk, and don't compose with on-chain workflows.

Sherwood fixes this: **hold stock tokens, buy protection, keep upside, define downside.**

---

## How It Works

### The Simple Version

1. **You hold 5 TSLA** at entry price $100 = $500 position
2. **You buy 80% protection for 7 days** = pay $12.50 USDG premium
3. **Your protection floor is $400** (80% of entry value)
4. **At expiry:**
   - TSLA rises to $120 → you get 100% of upside ($600), no payout needed
   - TSLA falls to $60 → you get $400 floor, Sherwood pays you $100 USDG
   - TSLA falls to $90 → you get $450, no payout (still above floor)

### The Formula

```
protectedValue = amount × entryPrice × protectionLevel
currentValue = amount × settlementPrice
payout = max(0, protectedValue - currentValue)
```

**Key insight:** You keep all upside. Sherwood only covers the gap below your floor. The maximum possible payout is the floor value itself (`protectedValue`) — that's what the vault reserves per note.

---

## Core Concepts

### Protection Note

A Protection Note is an immutable on-chain record — a plain struct addressed by `noteId` in the `ProtectionNote` contract:
- **Owner:** The buyer, fixed at creation. Notes are deliberately **not transferable**: protection is priced for the buyer, so it settles to the account that bought it.
- **Asset:** Which stock token (TSLA, AMZN, NFLX, PLTR, AMD)
- **Amount:** How many tokens to protect
- **Entry Price:** Verified Chainlink price at creation time
- **Protection Level:** 70%, 80%, or 90% floor
- **Duration:** 1, 7, 14, or 30 days
- **Premium:** Paid upfront in USDG
- **Status:** ACTIVE → SETTLED (with or without payout)

Once created, terms are immutable. No modifications, no surprises. To buy protection you must **hold the stock token you're protecting** — Sherwood insures a real position, it isn't a naked bet. The token is never taken into custody: you keep the shares and all the upside, and only the downside is settled in USDG against the price difference.

### Protection Levels

V1 supports three predefined tiers:

| Tier | Floor | Premium | Use Case |
|------|-------|---------|----------|
| **70%** | Covers 30% drop | Lower cost | Moderate risk tolerance |
| **80%** | Covers 20% drop | Medium cost | Balanced hedge |
| **90%** | Covers 10% drop | Higher cost | Strong downside fear |

Example: $1,000 position
- 70% protection → floor is $700
- 80% protection → floor is $800
- 90% protection → floor is $900

### Premium Model

Transparent, protocol-defined pricing (no black box):

```
Premium Rate = Base Rate (1%) + Protection Tier Risk + Duration Risk
Premium = Position Value × Premium Rate
```

Example for 80% protection, 7 days:
- Base rate: 1.0%
- 80% tier: +1.0%
- 7-day duration: +0.5%
- **Total: 2.5%**
- On $500 position = $12.50 USDG

V1 deliberately does not use Black-Scholes, implied volatility, or options pricing models. That's V2.

### Vault & Capacity

Sherwood holds collateral in a Vault. The protocol never sells more protection than it can cover.

Example:
- Vault has $1,000 USDG collateral
- 20% reserve buffer required
- Maximum active liability: $800
- If you request $200 protection and $700 is already reserved, Sherwood rejects your request

This guarantee is checked at creation time, before your premium is collected. If anything in the creation flow reverts, nothing is collected.

The buffer is part of the guarantee, not a target the owner can quietly spend: `withdrawSurplus` is capped at free capacity, so an owner withdrawal can never leave reserved collateral above the usable line, and `setBufferBps` refuses a raise that would strand collateral already reserved under a smaller buffer. Emptying the vault is an explicit act — settle the notes, clear the buffer, withdraw.

### Settlement

Protection Notes settle using verified price data from Chainlink:

1. At expiry, Chainlink oracle returns settlement price (freshness- and sequencer-uptime-checked)
2. Contract calculates: `payout = max(0, protectedValue - currentValue)`
3. Note status → SETTLED
4. Vault executes USDG transfer (or zero if price stayed above floor)

Prices are never user-supplied — they always come from Chainlink. A stale price is not silently used: the oracle checks each feed's round freshness and **reverts** if it's too old, so settlement simply waits for a fresh round rather than settling on frozen data. No contract can promise a price source is never stale; Sherwood guarantees it never *acts* on a stale one.

Settlement is permissionless and has no deadline: a note settles against the first price the oracle accepts at or after expiry. That is bounded by construction — the payout can never exceed the liability already reserved for that note, so a buyer waiting out a worse price is spending collateral the vault set aside for them, not exposing the vault.

---

## Architecture

```
                 USER
                  │
                  ▼
          SHERWOODNOTES WEB APP
                  │
                  ▼
          PROTECTION NOTE (noteId)
                  │
         ┌────────┴────────┐
         ▼                 ▼
   STOCK TOKEN         USDG VAULT
    (Holdings)         (Collateral)
         │                 │
         ▼                 ▼
   CHAINLINK          SHERWOOD
   PRICE DATA         SETTLEMENT
         │                 │
         └────────┬────────┘
                  ▼
            USDG PAYOUT
```

### Smart Contracts

**SherwoodVault.sol** — Holds USDG collateral, reserves capacity, executes payouts
- `deposit()` — Deposit USDG collateral
- `reserveFor()` — Reserve capacity and collect premium for a new note (called only by ProtectionNote; capacity checked before any token movement, and the reserve is recorded *before* the premium is pulled, so a hooked token can't re-enter past the check)
- `settlePayout()` — Pay USDG to the buyer and release the reserved liability (payout ≤ liability, re-checked on-chain; the release is booked before the transfer)
- `withdrawSurplus()` — Owner withdrawal, capped at `availableCapacity()`: never reserved collateral, never the reserve buffer. Wind-down is settle → `setBufferBps(0)` → withdraw
- State: `totalDeposits`, `reserved`, `availableCapacity()`, `bufferBps`

**ProtectionNote.sol** — Creates and settles Protection Notes as structs keyed by `noteId` (non-transferable; no ERC-721 surface)
- `create()` — Read verified entry price, check vault capacity, collect premium, record the note
- `settle()` — Settle an expired note; pays the recorded buyer
- `quote()` — Live on-chain quote so the UI never recomputes prices client-side
- `calculatePayout()` — Spec payout formula for a hypothetical settlement price
- State: `notes(noteId)`, `nextId`, per-note status

**ProtectionOracle.sol** — Retrieves and validates prices
- `getPrice()` — Chainlink `latestRoundData()` with round-completeness and freshness checks
- **L2 sequencer-uptime gate** — Robinhood Chain is an Arbitrum-based L2, and during a sequencer outage a feed's `updatedAt` can look fresh while the round still carries a pre-outage price. When an uptime feed is configured, every price read first checks Chainlink's standard aggregator (0 = up, 1 = down) and a post-restart grace window (default 3600 s, owner-capped at 1 day), rejecting `SequencerDown` / `SequencerGracePeriodNotOver`. It fails closed: a malformed uptime round is treated as down. Unset (`address(0)`) means the chain publishes no feed and the gate is off — the state of testnet 46630 today.
- Rejects stale, invalid, or unsupported prices; no caching, no fallbacks

**AssetRegistry.sol** — Registers supported stock tokens and their Chainlink feeds. Feeds must report 8 decimals — the scale every price formula in `ProtectionMath` is written at — and a feed that doesn't is rejected at registration *and* at rotation (`UnsupportedFeedDecimals`), because a 6- or 18-decimal feed would silently mis-price every note against it. Owner-gated: `registerAsset`, `setAssetActive`, `setAssetFeed` are admin-only; read views are permissionless.

---

## Tech Stack

- **Chain:** Robinhood Chain — mainnet (4663) and testnet (46630), an Arbitrum-based L2 with ETH gas
- **Smart Contracts:** Solidity (Foundry for compile/test/deploy)
- **Settlement Currency:** USDG (Paxos Global Dollar)
- **Price Oracle:** Chainlink Price Feeds (`AggregatorV3`)
- **Frontend:** SherwoodNotes — Next.js + React + TypeScript, wagmi / viem, Tailwind CSS

---

## Verified Environment Facts

These were verified against official docs (September 2026):

| Fact | Value | Source |
|---|---|---|
| Testnet chain ID | `46630` | docs.robinhood.com/chain/connecting |
| Mainnet chain ID | `4663` | docs.robinhood.com/chain/connecting |
| Testnet RPC (public, rate-limited) | `https://rpc.testnet.chain.robinhood.com` | docs.robinhood.com/chain/connecting |
| Testnet explorer | `https://explorer.testnet.chain.robinhood.com` | docs.robinhood.com/chain/connecting |
| Mainnet explorer | `https://robinhoodchain.blockscout.com` | docs.robinhood.com/chain/connecting |
| Gas token | ETH | docs.robinhood.com/chain |
| USDG on mainnet | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | docs.robinhood.com/chain/contracts |
| USDG on testnet | `0x7E955252E15c84f5768B83c41a71F9eba181802F` | testnet explorer, verified 2026-09-12: ERC-1967 proxy to verified Paxos `contracts/stablecoins/USDG.sol` (`0xF0863D7A29a55d0c4263c11bFac754312ff078DF`); implementation bytecode is byte-identical to the mainnet USDG implementation except self-references and one chain constant |
| Testnet USDG faucet | 100 USDG per claim, dripped continuously by ops wallet `0xcc9644EC26A647de0B9b86f1560d5180232f70a3`; claim site `https://testnet.robinhoodchain.com` — **no claim ever reached protocol wallets** (balance still 0 as of 2026-09-13; escalated to Robinhood dev support), which is why the testnet stack settles on MockUSDG below | testnet explorer transfer history, observed live 2026-09-12; re-checked 2026-09-13 |
| **Settlement token on testnet (protocol default)** | MockUSDG `0x8c4aa106a0A0d9ECAeD5C87e1AE766aa8Efbf006` — "Mock USDG", symbol `USDG`, **6 decimals**, public `faucet()` = **1,000 tokens per address per 24h** (`FAUCET_AMOUNT = 1000e6`, `FAUCET_COOLDOWN = 1 days`), `mintLocked = true` so the faucet is the only open supply; testnet-only, admin `0x0b64B35c6Dd23944D6D4029864D2cA2AA1B66422` can still mint/burn | source-verified on the testnet explorer as `src/mocks/MockUSDG.sol` (solc 0.8.28, creation tx `0x78a713a5d9b5d897f47809ead0f8afd540c0a0dae34c47903a028d471756e089`); constants read on-chain and one live claim proven 2026-09-13: tx `0x6e8c867dfb0f9b2b057bac9cbe6fc82979dac7ec701f1b7cdb0af1bc8a4122e6` minted exactly `1_000_000_000`, immediate retry reverted `FaucetCooldown(1789363365)` = claim timestamp + 86400 |
| Stock tokens on testnet (18 dec, `BeaconProxy` → verified `Stock` impl) | TSLA `0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E`, AMZN `0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02`, NFLX `0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93`, PLTR `0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0`, AMD `0x71178BAc73cBeb415514eB542a8995b82669778d` | testnet explorer token list (same deployer infra as the verified Beacon/`Stock` contracts) |
| Price feeds | Every Stock Token has a Chainlink feed (`AggregatorV3`, `latestRoundData()`); USD feeds are 8 decimals; updates are 24/5 with no heartbeats off-hours | docs.robinhood.com/chain/oracles-and-price-feeds |

**Open items — verify at deploy time, not assumed:**
- **Chainlink feed availability on testnet** — Chainlink's tokenized-equity feed list currently covers Robinhood Chain mainnet; if testnet lacks feeds, register demo feeds and disclose it.
- **Stock Token API (`/rhj/assets`, `/rhj/prices/{SYM}`)** — investigated 2026-09-12 as a settlement source, **not integrated**: official and public (HTTP 200, no auth; 194 assets), but every deployment is mainnet chain 4663 (nothing for testnet), responses are unsigned, and `bid`/`ask` are raw underlying prices — explicitly *not* multiplier-adjusted, unlike the on-chain Chainlink feeds. Feeding it on-chain would require a trusted updater, breaking the invariant that settlement prices are publicly verifiable from chain data. It is a good display-only source (market context, halt status) and a future mainnet registry discovery path.
- **Feed addresses** — per Chainlink's guidance, never hardcode: read them from the Chainlink Robinhood feeds page at deploy and pass via `FEED_<SYMBOL>` env.
- **Sequencer uptime** — the check Robinhood docs recommend before trusting prices is **implemented** (2026-09-14): `ProtectionOracle` gates every price read on Chainlink's L2 sequencer uptime feed and a post-restart grace window, failing closed on malformed data (see *Smart Contracts*). **No uptime feed address is verified for either Robinhood Chain network yet**, so the gate ships disabled; it goes live by passing `SEQUENCER_UPTIME_FEED` at deploy, the same way `FEED_<SYMBOL>` supplies equity feeds. Until then the staleness guard (default 72h, per-feed capped at 7 days) is the only price-freshness protection, and it is what rejects outage-frozen prices.

---

## Quick Start

```bash
# Contracts (Foundry)
forge build
forge test

# Deploy to Robinhood Chain testnet
export RPC_URL=https://rpc.testnet.chain.robinhood.com
export PRIVATE_KEY=your-testnet-key
export SETTLEMENT_TOKEN=0x8c4aa106a0A0d9ECAeD5C87e1AE766aa8Efbf006   # optional: MockUSDG is already the 46630 default; point at 0x7E95... when real testnet USDG becomes claimable
export TOKEN_TSLA=0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E FEED_TSLA=0x...   # repeat per asset (AMZN, NFLX, PLTR, AMD); feeds must report 8 decimals
export SEQUENCER_UPTIME_FEED=0x... SEQUENCER_GRACE_PERIOD=3600   # optional: L2 sequencer gate; unset = off, which is correct for a chain with no feed
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
# Source verification (Blockscout):
forge verify-contract --chain-id 46630 --verifier blockscout \
  --verifier-url https://explorer.testnet.chain.robinhood.com/api <ADDRESS> <SRC>:<CONTRACT> [--constructor-args <abi-encoded>]

# Fund a wallet for the demo (testnet only): claims the settlement token, then
# DemoCreate.s.sol deposits into the vault and buys a 1-day note.
forge script script/Faucet.s.sol --rpc-url $RPC_URL --broadcast     # 1,000 per address per 24h
forge script script/DemoCreate.s.sol --rpc-url $RPC_URL --broadcast # after expiry: DemoSettle.s.sol

# Frontend (SherwoodNotes)
cd frontend
npm install
npm run dev
```

Then open http://localhost:3000:
1. Connect wallet on Robinhood Chain testnet (testnet settlement tokens required — claim them with `script/Faucet.s.sol` or the site faucet at testnet.robinhoodchain.com)
2. View your stock tokens
3. Select asset and create a Protection Note
4. Monitor on-chain settlement
5. View payout receipt (if triggered)

### Frontend on Vercel

Deployable with zero configuration. The v4 testnet addresses and the settlement token are
built into `frontend/lib/addresses.ts` (source of truth: `deploy/deployments.json`), fonts load
at runtime rather than at build time, and every page prerenders as static content — so the
build needs no secrets and no network beyond `npm ci` from the committed lockfile.

1. Import the repo on Vercel, set **Root Directory** to `frontend` (Next.js is auto-detected;
   `outputFileTracingRoot` in `next.config.mjs` pins the workspace root there so nothing above
   the checkout can pull the build graph sideways)
2. Deploy — no env vars required
3. Optional env vars: `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` (unlocks mobile-wallet QR via WalletConnect; get one free at cloud.walletconnect.com — with it unset the connector is simply not registered, which is the intended degradation), `NEXT_PUBLIC_RPC_ROBINHOOD_TESTNET` (a rate-limit-free RPC instead of the public one)
4. To buy protection on the deployed app you need the testnet settlement token: MockUSDG
   (`0x8c4aa106a0A0d9ECAeD5C87e1AE766aa8Efbf006`), 1,000 per address per 24h — claim it with
   `forge script script/Faucet.s.sol --rpc-url $RPC_URL --broadcast`, or from the site faucet
   at testnet.robinhoodchain.com for the official testnet USDG

All contract addresses fall back to the deployed testnet values and can be overridden per
environment with `NEXT_PUBLIC_*` without touching code. `frontend/.env.local` does the same
thing locally and is gitignored, so a deploy can never inherit a local-only address.

---

## Project Structure

```
sherwood/
├── README.md                        # This file
├── BUILD_SPEC.md                    # Complete technical specification
├── DESIGN.md                        # Frontend design system (midnight theme)
├── foundry.toml                     # Foundry configuration
│
├── src/                             # Solidity contracts
│   ├── SherwoodVault.sol            # Collateral, capacity checks, payouts
│   ├── ProtectionNote.sol           # Note creation, quoting, settlement
│   ├── ProtectionOracle.sol         # Chainlink feed validation
│   ├── AssetRegistry.sol            # Owner-gated asset + feed registry
│   ├── ProtectionMath.sol           # Pure premium/payout/conversion math
│   ├── Ownable.sol                  # Minimal ownership control
│   └── interfaces/                  # IERC20, IAggregatorV3 (vendored)
│
├── test/                            # Foundry tests (dependency-free TestBase)
├── script/                          # Deploy.s.sol, Config.s.sol (chain config), Faucet.s.sol, demo scripts
├── assets/                          # Logo, opengraph card, brand art
└── frontend/                        # SherwoodNotes (Next.js App Router)
    ├── app/                         # Dashboard, Protect, Notes, Vault pages
    ├── components/                  # Header, shared UI
    └── lib/                         # ABIs, addresses, chain definition, formatting
```

---

## User Flow

**Step 1:** Connect wallet to Robinhood Chain testnet

**Step 2:** App displays your stock token balances
```
Your Holdings
5 TSLA
3 AMZN
10 AMD
```

**Step 3:** Select an asset to protect
```
Protect TSLA
```

**Step 4:** Configure protection
```
Amount:       5 TSLA
Protection:   80%
Duration:     7 Days
```

**Step 5:** Review terms
```
Position Value:     $500
Protection Floor:   $400
Premium:            $12.50 USDG
Max Payout:         $400
Expires:            Sep 29, 2026
```

**Step 6:** Approve USDG and create note
- Chainlink reads entry price
- Vault reserves capacity
- Premium collected
- Protection Note recorded on-chain

**Step 7:** Note is now ACTIVE
- Monitor your position
- Watch price movement
- View on-chain settlement record

**Step 8:** At expiry
- Chainlink reads settlement price
- Contract calculates payout
- USDG transferred (if triggered) or liability released
- Note status → SETTLED

---

## Settlement States

```
CREATE
  │
  ▼
ACTIVE (waiting for expiry)
  │
  ├── Price > Floor
  │    ↓
  │  SETTLED (no payout, you kept upside)
  │
  └── Price < Floor
       ↓
     SETTLED (payout = floor - current)
```

---

## Build Roadmap

**Phase 1 (Core MVP) — Must Ship**
- Wallet connection to Robinhood Chain testnet
- Read real stock token balances
- Deploy SherwoodVault with collateral
- Create Protection Notes with verified entry price
- Reserve vault capacity and prevent over-commitment
- Calculate premiums transparently (base + tier + duration)
- Settle notes using Chainlink prices
- Execute USDG payouts (or zero if price stays above floor)
- Display on-chain settlement history and proof of payout

**Phase 2 (Improvements) — If Time**
- Multiple coverage tiers (configurable per asset)
- Vault analytics dashboard (utilization, reserves, active liability)
- Protection provider deposits (for liquidity)
- Risk monitoring and capacity alerts
- Premium utilization curves

**Phase 3 (Nice-to-Have) — Only If Remaining Time**
- Session-based permissions for automation
- Additional chains, if a deploy target justifies itself

Shipped beyond the phases above: the L2 sequencer-uptime gate in `ProtectionOracle` (2026-09-14), 8-decimal feed validation in `AssetRegistry`, and checks-effects-interactions ordering across the vault and note (pinned by `test/Reentrancy.t.sol`).

---

## Critical Rules

**No Mocked Flows** — Every primary flow runs against real testnet infrastructure: real stock token balances, real wallet connections, real on-chain Protection Notes, real ERC-20 settlement transfers. Two substitutes exist on testnet, both disclosed, and both are addresses rather than code paths: prices come from owner-set `DemoFeed` stand-ins (Chainlink publishes no tokenized-equity feeds on 46630) and the settlement token is `MockUSDG`, a source-verified 6-decimal faucet token, because Robinhood's testnet USDG drip never funded a protocol wallet. Mainnet uses real Chainlink feeds and canonical USDG with no protocol change — only `script/Config.s.sol` differs, and it refuses the mock on mainnet outright.

**No Overbuild** — Sherwood's core demo is: Real Stock Token → User Creates Protection Note → Verified Price → On-Chain Terms → Real Settlement. That alone is a complete financial primitive.

**Prices from Chainlink Only** — Never accept user-supplied, estimated, or cached prices. Always verify freshness. Always reject stale, invalid, or unsupported assets. On an L2, freshness is not enough: while the sequencer is down a round can look current and carry a pre-outage price, so no price is used unless the chain's uptime feed reports the sequencer up and clear of its restart grace window (and the gate fails closed when the uptime data is malformed).

**No TODOs** — Write complete implementations. If something is blocked, log it as a known limitation in the commit message, not as a TODO marker.

---

## Why Sherwood Works

1. **Simple UX:** Users think in natural terms (floor price, duration, premium). No options jargon.
2. **Transparent Pricing:** No Black-Scholes, no hidden margin. Premium = Base + Tier + Duration.
3. **Minimal surface:** Notes are plain structs keyed by `noteId` — no token-standard attack surface, no approval flows. The contract is readable top to bottom.
4. **Verifiable:** Chainlink prices are public. Payouts are auditable. No surprises.
5. **Immutable Terms:** Once created, a Protection Note cannot be changed. Terms are guaranteed.

---

## Developer Resources

- Robinhood Chain Docs: https://docs.robinhood.com/chain/
- Chainlink Robinhood feeds: https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood
- Foundry (build/test): https://book.getfoundry.sh/
- viem (TypeScript): https://viem.sh/
- wagmi (React): https://wagmi.sh/
- Arbitrum Docs (Robinhood Chain is Arbitrum-based): https://docs.arbitrum.io/

---

## Contact & Contribution

See `BUILD_SPEC.md` for the complete technical specification and invariants list.

---

**Keep the upside. Define the downside.**
