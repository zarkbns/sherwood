// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AssetRegistry} from "./AssetRegistry.sol";
import {ProtectionOracle} from "./ProtectionOracle.sol";
import {ProtectionMath} from "./ProtectionMath.sol";
import {SherwoodVault} from "./SherwoodVault.sol";
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

        // Position guard: the caller must hold the tokens they are protecting. Checked
        // before any oracle read, capacity reservation, or premium movement, so a failed
        // hold collects and reserves nothing. Balance is verified, not transferred — the
        // buyer keeps their stock and all upside; only the downside is insured.
        // Scoped so its stack slot is freed before the pricing locals below.
        {
            uint256 held = IERC20(asset).balanceOf(msg.sender);
            if (held < amount) revert InsufficientPosition(asset, held, amount);
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

        AssetRegistry.Asset memory entry = registry.getAsset(note.asset);
        (uint256 settlementPrice8,) = oracle.getPrice(entry.feed, entry.maxStaleness);

        uint256 payoutUSD18 =
            ProtectionMath.payout(_eligibleAmount(note), note.entryPrice, note.level, settlementPrice8);
        uint256 payoutToken = ProtectionMath.toTokenUnits(payoutUSD18, vault.token().decimals());

        vault.settlePayout(noteId, recipient, note.liabilityToken, payoutToken);

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
    ///         so the view never overstates what settlement can actually pay.
    function calculatePayout(uint256 noteId, uint256 settlementPrice8) external view returns (uint256) {
        Note storage note = notes[noteId];
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
