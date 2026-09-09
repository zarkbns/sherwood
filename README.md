# Sherwood 🛡️

> Programmable downside protection for tokenized stocks on Arbitrum chains.

Sherwood lets users protect their stock positions against downside risk while keeping all their upside. Buy a Protection Note, define your floor, and settle with verified prices.

*Built for the Arbitrum Open House Singapore: Online Buildathon — deployed on Robinhood Chain and Arbitrum One.*

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

**Key insight:** You keep all upside. Sherwood only covers the gap below your floor.

---

## Core Concepts

### Protection Note

A Protection Note is an immutable on-chain contract specifying:
- **Asset:** Which stock token (TSLA, AMZN, NFLX, PLTR, AMD)
- **Amount:** How many tokens to protect
- **Entry Price:** Verified price at creation time
- **Protection Level:** 70%, 80%, or 90% floor
- **Duration:** 7, 14, or 30 days
- **Premium:** Paid upfront in USDG
- **Status:** ACTIVE → SETTLABLE → SETTLED (with or without payout)

Once created, terms are immutable. No modifications, no surprises.

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

This guarantee is checked at creation time, before your Premium is collected.

### Settlement

Protection Notes settle using verified price data from Chainlink:

1. At expiry, Chainlink oracle returns settlement price
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
          SHERWOOD WEB APP
                  │
                  ▼
          PROTECTION NOTE
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

**SherwoodVault.sol** — Holds collateral, reserves capacity, executes payouts
- `deposit()` — Deposit USDG collateral
- `reserve()` — Reserve capacity for a new Protection Note
- `release()` — Release capacity if note expires without payout
- `payout()` — Pay USDG to claimant
- State: `totalCollateral`, `reservedCollateral`, `activeLiability`

**ProtectionNote.sol** — Creates and manages Protection Notes
- `create()` — Mint a new Protection Note
- `settle()` — Settle a note using oracle price
- `calculatePayout()` — Compute payout amount
- State: notes array, expiry tracking, status flags

**ProtectionOracle.sol** — Retrieves and validates prices
- `getEntryPrice()` — Entry price (Chainlink)
- `getSettlementPrice()` — Settlement price (Chainlink)
- `validate()` — Reject stale, invalid, or unsupported prices

**AssetRegistry.sol** — Whitelists supported stock tokens
- Stores enabled assets (TSLA, AMZN, NFLX, PLTR, AMD)
- Maps each asset to Chainlink price feed
- Enables/disables assets permissionlessly

---

## Tech Stack

- **Blockchain:** Dual-chain — Robinhood Chain testnet + Arbitrum One / Arbitrum Sepolia (EVM-compatible)
- **Smart Contracts:** Solidity (Foundry for compile/test/deploy)
- **Frontend:** Next.js + React + TypeScript
- **Web3 SDK:** viem / wagmi
- **Styling:** Tailwind CSS
- **Price Oracle:** Chainlink Price Feeds
- **Settlement Currency:** USDG (Robinhood Chain) / USDC (Arbitrum One)
- **Optional:** ZeroDev (Account Abstraction for UX)
- **Optional:** Lighter (Risk management / hedging)

---

## Quick Start

```bash
# Install dependencies
npm install

# Deploy contracts (Robinhood Chain testnet or Arbitrum via RPC_URL)
npm run deploy

# Start frontend dev server
npm run dev
```

Then open http://localhost:3000:
1. Connect wallet (testnet USDG required)
2. View your stock tokens
3. Select asset and create a Protection Note
4. Monitor on-chain settlement
5. View payout receipt (if triggered)

---

## Project Structure

```
sherwood/
├── README.md                        # This file
├── AGENTS.md                        # AI agent build contract
├── BUILD_SPEC.md                    # Complete technical specification
│
├── contracts/
│   ├── SherwoodVault.sol           # Collateral and payout management
│   ├── ProtectionNote.sol          # Protection Note creation and settlement
│   ├── ProtectionOracle.sol        # Price feed integration
│   ├── AssetRegistry.sol           # Supported stock token registry
│   │
│   ├── interfaces/
│   │   ├── IProtectionVault.sol
│   │   ├── IProtectionOracle.sol
│   │   └── IERC20.sol
│   │
│   └── libraries/
│       └── ProtectionMath.sol      # Premium and payout calculations
│
├── src/
│   ├── services/
│   │   ├── protectionService.ts   # Create and manage Protection Notes
│   │   ├── vaultService.ts        # Collateral and capacity queries
│   │   └── oracleService.ts       # Price feed integration
│   ├── types/
│   │   └── index.ts               # TypeScript interfaces
│   └── utils/
│       └── web3.ts                # viem/wagmi setup
│
├── frontend/
│   ├── pages/
│   │   ├── index.tsx              # Dashboard
│   │   ├── protect.tsx            # Create Protection Note
│   │   ├── my-protection.tsx       # Active notes
│   │   └── vault.tsx              # Vault stats
│   ├── components/
│   │   └── [React components]
│   └── styles/
│
├── tests/
│   ├── SherwoodVault.test.ts
│   ├── ProtectionNote.test.ts
│   └── Settlement.test.ts
│
├── deploy/
│   ├── deploy.ts                  # Deployment script
│   └── deployments.json           # Deployed addresses
│
└── package.json
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
Max Payout:         $500
Expires:            Sep 29, 2025
```

**Step 6:** Approve USDG and create note
- Chainlink reads entry price
- Vault reserves capacity
- Premium collected
- Protection Note minted

**Step 7:** Note is now ACTIVE
- Monitor your position
- Watch price movement
- View on-chain settlement record

**Step 8:** At expiry
- Chainlink reads settlement price
- Contract calculates payout
- USDG transferred (if triggered) or released
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
- ZeroDev smart account integration
- Session-based permissions for automation
- Lighter hedge allocation (risk management delegate)
- Hedge mandate tracking and audit trail
- Executor performance monitoring

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
3. **Composable:** Protection Notes are on-chain objects, not tied to a single exchange.
4. **Verifiable:** Chainlink prices are public. Payouts are auditable. No surprises.
5. **Immutable Terms:** Once created, a Protection Note cannot be changed. Terms are guaranteed.

---

## Key Assumptions

- **Robinhood Chain Testnet:** USDG stablecoin available and working
- **Arbitrum One:** tokenized stocks (Robinhood rTSLA etc.) + Chainlink US equity price feeds live on mainnet
- **Chainlink:** Price feeds for TSLA, AMZN, NFLX, PLTR, AMD available on target chains
- **EVM Compatibility:** Robinhood Chain is EVM-compatible
- **Account Abstraction (optional):** ZeroDev is a nice-to-have, not core to Phase 1

---

## Developer Resources

- Robinhood Chain Docs: https://docs.robinhood.com/chain/
- Arbitrum Docs: https://docs.arbitrum.io/
- Chainlink Price Feeds: https://docs.chain.link/price-feeds
- Foundry (build/test): https://book.getfoundry.sh/
- viem (TypeScript): https://viem.sh/
- wagmi (React): https://wagmi.sh/

---

## Contact & Contribution

See `AGENTS.md` for build guidelines and autonomous development contract.

---

**Keep the upside. Define the downside.**
