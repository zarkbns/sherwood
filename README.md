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
- **Duration:** 7, 14, or 30 days
- **Premium:** Paid upfront in USDG
- **Status:** ACTIVE → SETTLED (with or without payout)

Once created, terms are immutable. No modifications, no surprises. Holding the stock token is not required — the instrument is cash-settled on the price difference.

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

### Settlement

Protection Notes settle using verified price data from Chainlink:

1. At expiry, Chainlink oracle returns settlement price (freshness-checked)
2. Contract calculates: `payout = max(0, protectedValue - currentValue)`
3. Vault executes USDG transfer (or zero if price stayed above floor)
4. Note status → SETTLED

Prices are never user-supplied. Prices are never stale. Prices are always from Chainlink.

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
- `reserveFor()` — Reserve capacity and collect premium for a new note (called only by ProtectionNote; capacity checked before any token movement)
- `settlePayout()` — Pay USDG to the buyer and release the reserved liability (payout ≤ liability, re-checked on-chain)
- `withdrawSurplus()` — Owner withdrawal of unencumbered funds only
- State: `totalDeposits`, `reserved`, `availableCapacity()`, `bufferBps`

**ProtectionNote.sol** — Creates and settles Protection Notes as structs keyed by `noteId` (non-transferable; no ERC-721 surface)
- `create()` — Read verified entry price, check vault capacity, collect premium, record the note
- `settle()` — Settle an expired note; pays the recorded buyer
- `quote()` — Live on-chain quote so the UI never recomputes prices client-side
- `calculatePayout()` — Spec payout formula for a hypothetical settlement price
- State: `notes(noteId)`, `nextId`, per-note status

**ProtectionOracle.sol** — Retrieves and validates prices
- `getPrice()` — Chainlink `latestRoundData()` with round-completeness and freshness checks
- Rejects stale, invalid, or unsupported prices; no caching, no fallbacks

**AssetRegistry.sol** — Registers supported stock tokens and their Chainlink feeds. Owner-gated: `registerAsset`, `setAssetActive`, `setAssetFeed` are admin-only; read views are permissionless.

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
| Price feeds | Every Stock Token has a Chainlink feed (`AggregatorV3`, `latestRoundData()`); USD feeds are 8 decimals; updates are 24/5 with no heartbeats off-hours | docs.robinhood.com/chain/oracles-and-price-feeds |

**Open items — verify at deploy time, not assumed:**
- **USDG address on testnet** — not published in the docs yet; confirm on the testnet explorer and set `SETTLEMENT_TOKEN` for the deploy script (the vault reads `decimals()` on-chain regardless).
- **Chainlink feed availability on testnet** — Chainlink's tokenized-equity feed list currently covers Robinhood Chain mainnet; if testnet lacks feeds, register demo feeds and disclose it.
- **Stock token addresses** — read from the live on-chain asset registry / explorer at deploy; the protocol is asset-agnostic and registers whatever tokens exist per chain.
- **Feed addresses** — per Chainlink's guidance, never hardcode: read them from the Chainlink Robinhood feeds page at deploy and pass via `FEED_<SYMBOL>` env.
- **Sequencer uptime** — Robinhood Chain docs recommend an L2 sequencer check before trusting prices; the oracle's freshness guard (default 72h staleness, per-feed capped at 7 days) already rejects outage-frozen prices. A dedicated sequencer-uptime feed integration is a known V2 item.

---

## Quick Start

```bash
# Contracts (Foundry)
forge build
forge test

# Deploy to Robinhood Chain testnet
export RPC_URL=https://rpc.testnet.chain.robinhood.com
export PRIVATE_KEY=your-testnet-key
export SETTLEMENT_TOKEN=0x...        # testnet USDG (verify on explorer first)
export TOKEN_TSLA=0x... FEED_TSLA=0x...   # repeat per asset (AMZN, NFLX, PLTR, AMD)
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify

# Frontend (SherwoodNotes)
cd frontend
npm install
npm run dev
```

Then open http://localhost:3000:
1. Connect wallet on Robinhood Chain testnet (testnet USDG required)
2. View your stock tokens
3. Select asset and create a Protection Note
4. Monitor on-chain settlement
5. View payout receipt (if triggered)

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
├── script/                          # Deploy.s.sol + Config.s.sol (chain config)
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
- Multiple durations (7, 14, 30 days, etc.)
- Vault analytics dashboard (utilization, reserves, active liability)
- Protection provider deposits (for liquidity)
- Risk monitoring and capacity alerts
- Premium utilization curves

**Phase 3 (Nice-to-Have) — Only If Remaining Time**
- Session-based permissions for automation
- Sequencer-uptime feed integration for the oracle
- Additional chains, if a deploy target justifies itself

---

## Critical Rules

**No Mocks** — All primary flows interact with real testnet infrastructure: real stock token balances, real Chainlink prices, real wallet connections, real Protection Notes, real USDG settlement.

**No Overbuild** — Sherwood's core demo is: Real Stock Token → User Creates Protection Note → Verified Price → On-Chain Terms → Real Settlement. That alone is a complete financial primitive.

**Prices from Chainlink Only** — Never accept user-supplied, estimated, or cached prices. Always verify freshness. Always reject stale, invalid, or unsupported assets.

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
