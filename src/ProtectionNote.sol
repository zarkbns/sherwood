// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AssetRegistry} from "./AssetRegistry.sol";
import {ProtectionOracle} from "./ProtectionOracle.sol";
import {ProtectionMath} from "./ProtectionMath.sol";
import {SherwoodVault} from "./SherwoodVault.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/// @title ProtectionNote
/// @notice Cash-settled downside protection. Each note is a plain struct addressed by
///         noteId that fixes asset, amount, entry price, floor level, and expiry at
///         creation. Notes are deliberately not transferable: protection is priced for
///         the buyer, so it stays with them. Settling reads the Chainlink settlement
///         price and pays max(0, floor - current) from the vault; the buyer keeps all
///         upside. The payout basis is the position the owner still holds at settlement,
///         so sold stock stops being covered; the reserve always releases.
contract ProtectionNote {
    enum Status {
        ACTIVE,
        SETTLED
    }

    struct Note {
        address owner; // buyer, fixed at creation
        address asset;
        uint256 amount; // stock token units, 18 dec
        uint256 entryPrice; // USD, 8 dec, Chainlink at creation
        uint256 level; // 18-dec fraction, e.g. 0.8e18
        uint256 expiry; // unix seconds
        uint256 premiumUSD18; // premium collected, USD-18
        uint256 protectedUSD18; // floor value, USD-18
        uint256 liabilityToken; // reserved collateral, settlement-token units
        Status status;
    }

    AssetRegistry public immutable registry;
    ProtectionOracle public immutable oracle;
    SherwoodVault public immutable vault;

    mapping(uint256 => Note) public notes;
    uint256 public nextId;

    /// @notice Sum of `note.amount` across a holder's ACTIVE notes, per asset. Create
    ///         refuses to push it past the holder's current stock-token balance, so the
    ///         protection a (owner, asset) pair has sold is always backed by a position
    ///         that exists at the moment it is sold — one position cannot back an
    ///         unbounded stack of notes. Decremented when a note settles.
    mapping(address => mapping(address => uint256)) public activeProtected;

    /// @notice The settlement feed (and its staleness bound) each note was priced
    ///         against, bound at creation. Settlement reads these — never the registry's
    ///         current entry — so rotating an asset's feed can only ever affect notes
    ///         that do not exist yet; live notes always settle against the source they
    ///         were contracted with.
    mapping(uint256 => IAggregatorV3) public noteFeeds;
    mapping(uint256 => uint256) public noteMaxStaleness;

    event NoteCreated(
        uint256 indexed noteId,
        address indexed owner,
        address indexed asset,
        uint256 amount,
        uint256 entryPrice,
        uint256 level,
        uint256 expiry,
        uint256 premiumUSD18,
        uint256 protectedUSD18,
        uint256 liabilityToken
    );
    event NoteSettled(uint256 indexed noteId, uint256 settlementPrice, uint256 payoutToken, address indexed recipient);

    error UnsupportedAsset();
    error AssetInactive();
    error InvalidAmount();
    error InsufficientPosition(address asset, uint256 held, uint256 required);
    error NoteNotFound();
    error NotExpired();
    error AlreadySettled();

    /// @notice How long after expiry a note can still collect its payout. Bounded by the
    ///         longest term the rate table prices, so realized tail risk can never
    ///         outrun the duration the premium charged. Past the window the note still
    ///         settles — the reserve releases — but the payout is forfeited, like an
    ///         insurance claim past its filing deadline.
    uint256 public constant SETTLEMENT_WINDOW = 30 days;

    constructor(AssetRegistry _registry, ProtectionOracle _oracle, SherwoodVault _vault) {
        registry = _registry;
        oracle = _oracle;
        vault = _vault;
    }

    /// @notice Buy protection: reads the verified entry price, checks vault capacity,
    ///         collects the premium and reserves collateral atomically, then records
    ///         the note. The buyer must already hold `amount` of the stock token — this
    ///         protects a real position, not a naked bet. The stock is never taken into
    ///         custody; the note is cash-settled against the price difference.
    function create(address asset, uint256 amount, uint256 level, uint256 duration)
        external
        returns (uint256 noteId)
    {
        AssetRegistry.Asset memory entry = registry.getAsset(asset);
        if (!entry.registered) revert UnsupportedAsset();
        if (!entry.active) revert AssetInactive();
        if (amount == 0) revert InvalidAmount();

        // Reverts on unsupported level/duration before any state changes.
        ProtectionMath.premiumRateBps(level, duration);

        // Position guard, two halves. Per-call: the caller must hold the tokens they
        // are protecting. Aggregate: their whole stack of active notes on this asset
        // must stay inside that same holding — without it, one balance would pass this
        // check any number of times and the protocol would quietly sell N copies of one
        // position's downside, each individually "backed" by the same shares. Both are
        // checked before any oracle read, capacity reservation, or premium movement, so
        // a failed hold collects and reserves nothing. Balance is verified, never
        // transferred — the buyer keeps their stock and all upside; only the downside
        // is insured. Scoped so its stack slots are freed before the pricing locals.
        {
            uint256 held = IERC20(asset).balanceOf(msg.sender);
            uint256 committed = activeProtected[msg.sender][asset];
            if (held < amount) revert InsufficientPosition(asset, held, amount);
            if (committed + amount > held) revert InsufficientPosition(asset, held, committed + amount);
        }

        (uint256 price8,) = oracle.getPrice(entry.feed, entry.maxStaleness);

        uint256 premiumUSD18 = ProtectionMath.premium(
            ProtectionMath.usdValue(amount, price8), ProtectionMath.premiumRateBps(level, duration)
        );
        uint256 protectedUSD18 = ProtectionMath.protectedValue(amount, price8, level);

        uint8 tokenDecimals = vault.token().decimals();
        uint256 premiumToken = ProtectionMath.toTokenUnits(premiumUSD18, tokenDecimals);
        uint256 liabilityToken = ProtectionMath.toTokenUnits(protectedUSD18, tokenDecimals);

        noteId = nextId + 1;
        // Consume the id before the vault call. reserveFor pulls the premium from the
        // payer, and a settlement token with a transfer hook could re-enter create()
        // through that pull: with the id already taken the re-entrant call claims the
        // next one instead of overwriting this note and double-reserving its id. A
        // revert anywhere below still rolls the id back with the rest of the call.
        nextId = noteId;
        // Commit the exposure in the same pre-vault frame as the id: a hook re-entering
        // through the premium pull then sees a ledger that already counts this note's
        // position, so the re-entrant create is measured against a truthful aggregate.
        // A revert anywhere below rolls the increment back with the rest of the call.
        activeProtected[msg.sender][asset] += amount;
        // Bind the settlement basis at creation: this note settles against the feed it
        // was priced with, whatever the registry does to the asset later.
        noteFeeds[noteId] = entry.feed;
        noteMaxStaleness[noteId] = entry.maxStaleness;
        // Capacity check and premium collection happen inside the vault, atomically,
        // before the note exists. If anything reverts, nothing is collected.
        vault.reserveFor(noteId, msg.sender, premiumToken, liabilityToken);

        _record(noteId, msg.sender, asset, amount, price8, level, duration, premiumUSD18, protectedUSD18, liabilityToken);
    }

    /// @dev Separate frame keeps `create` under the stack limit without via-ir.
    function _record(
        uint256 noteId,
        address owner,
        address asset,
        uint256 amount,
        uint256 price8,
        uint256 level,
        uint256 duration,
        uint256 premiumUSD18,
        uint256 protectedUSD18,
        uint256 liabilityToken
    ) private {
        uint256 expiry = block.timestamp + duration;
        notes[noteId] = Note({
            owner: owner,
            asset: asset,
            amount: amount,
            entryPrice: price8,
            level: level,
            expiry: expiry,
            premiumUSD18: premiumUSD18,
            protectedUSD18: protectedUSD18,
            liabilityToken: liabilityToken,
            status: Status.ACTIVE
        });

        emit NoteCreated(noteId, owner, asset, amount, price8, level, expiry, premiumUSD18, protectedUSD18, liabilityToken);
    }

    /// @notice Settle an expired note. Permissionless. The payout goes to the buyer
    ///         recorded at creation — notes are not transferable, so protection always
    ///         settles to the account that bought it.
    ///
    ///         The payout is computed against `eligibleAmount`, the portion of the
    ///         protected position the buyer still holds at settlement. Protection covers
    ///         a real position, so selling part of the stock before expiry shrinks what
    ///         the downside pays proportionally, and selling all of it pays nothing. The
    ///         note still settles and the full reserved liability is always released — a
    ///         buyer who abandoned their position must never strand the vault's reserve,
    ///         and releasing it can only ever give capacity back.
    function settle(uint256 noteId) external {
        Note storage note = notes[noteId];
        if (noteId == 0 || noteId > nextId) revert NoteNotFound();
        if (note.status != Status.ACTIVE) revert AlreadySettled();
        if (block.timestamp < note.expiry) revert NotExpired();

        // Sealed before any external read. Eligibility below calls into the stock token,
        // and a balanceOf hook that re-entered settle() for this same id would otherwise
        // still see ACTIVE and draw the same liability twice. Every write here is rolled
        // back if anything later in the call reverts, so a failed settlement cannot
        // strand a note in SETTLED.
        note.status = Status.SETTLED;
        address recipient = note.owner;

        // The note's protected amount leaves the holder's aggregate exposure whether
        // the payout was full, partial, or zero — the note is gone either way, and the
        // position it committed should be free to back new protection. Cannot underflow:
        // create() credited exactly this amount for this note, and the status gate above
        // means it is consumed exactly once.
        activeProtected[recipient][note.asset] -= note.amount;

        // Claim window: the premium prices this note's term, so the payout is the floor
        // gap at the first accepted fresh price between expiry and expiry +
        // SETTLEMENT_WINDOW (the longest term the rate table prices). Past that deadline
        // the protection is over: the note still settles — a reserve must never strand
        // on an unclaimed or unreadable note — but the payout is forfeited. The forfeit
        // path skips the price read entirely, so even a permanently dead feed cannot
        // block the release.
        //
        // The price comes from the feed bound at creation — never the registry's current
        // entry — so a rotation can only reprice notes that do not exist yet.
        uint256 payoutToken;
        uint256 settlementPrice8;
        if (block.timestamp <= note.expiry + SETTLEMENT_WINDOW) {
            (settlementPrice8,) = oracle.getPrice(noteFeeds[noteId], noteMaxStaleness[noteId]);

            uint256 payoutUSD18 =
                ProtectionMath.payout(_eligibleAmount(note), note.entryPrice, note.level, settlementPrice8);
            payoutToken = ProtectionMath.toTokenUnits(payoutUSD18, vault.token().decimals());
        }

        vault.settlePayout(noteId, recipient, note.liabilityToken, payoutToken);

        // settlementPrice is 0 on the forfeit path: no price was read and none is owed.
        emit NoteSettled(noteId, settlementPrice8, payoutToken, recipient);
    }

    /// @notice The share of a note's protected position that still backs it: the smaller
    ///         of the protected amount and the balance its owner holds at settlement.
    ///         Read, never written — the note's recorded amount stays fixed and immutable,
    ///         only the payout it can produce shrinks.
    function _eligibleAmount(Note storage note) internal view returns (uint256) {
        uint256 held = IERC20(note.asset).balanceOf(note.owner);
        return held < note.amount ? held : note.amount;
    }

    /// @notice Payout this note would produce at a hypothetical settlement price (USD-18),
    ///         capped by the position the owner still holds — the same basis settle() uses,
    ///         so the view never overstates what settlement can actually pay. Zero once the
    ///         claim window has closed: settle() forfeits the payout past it too.
    function calculatePayout(uint256 noteId, uint256 settlementPrice8) external view returns (uint256) {
        Note storage note = notes[noteId];
        if (block.timestamp > note.expiry + SETTLEMENT_WINDOW) return 0;
        return ProtectionMath.payout(_eligibleAmount(note), note.entryPrice, note.level, settlementPrice8);
    }

    /// @notice Live quote for the create flow: reads the current oracle price and
    ///         returns exactly what create() would store at this instant, so the UI
    ///         never recomputes rates or prices client-side.
    function quote(address asset, uint256 amount, uint256 level, uint256 duration)
        external
        view
        returns (uint256 premiumUSD18, uint256 protectedUSD18, uint256 expiry)
    {
        AssetRegistry.Asset memory entry = registry.getAsset(asset);
        if (!entry.registered) revert UnsupportedAsset();
        if (!entry.active) revert AssetInactive();
        if (amount == 0) revert InvalidAmount();

        (uint256 price8,) = oracle.getPrice(entry.feed, entry.maxStaleness);
        premiumUSD18 = ProtectionMath.premium(
            ProtectionMath.usdValue(amount, price8), ProtectionMath.premiumRateBps(level, duration)
        );
        protectedUSD18 = ProtectionMath.protectedValue(amount, price8, level);
        expiry = block.timestamp + duration;
    }

    /// @notice True when a note exists, is active, and has passed its expiry.
    function isSettlable(uint256 noteId) external view returns (bool) {
        return noteId > 0 && noteId <= nextId && notes[noteId].status == Status.ACTIVE
            && block.timestamp >= notes[noteId].expiry;
    }
}
