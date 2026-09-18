// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "./interfaces/IERC20.sol";
import {Ownable} from "./Ownable.sol";

/// @title SherwoodVault
/// @notice Holds the settlement stablecoin, reserves collateral for active Protection
///         Notes, and executes payouts. Anyone can back protection by depositing: their
///         stake is tracked in shares, premiums flow in pro rata (minus Sherwood's fee
///         share), and payouts are borne pro rata. The protocol never sells more
///         protection than it can cover: `reserveFor` reverts unless reserved + liability
///         fits inside deposits minus the reserve buffer, the check always runs before
///         any premium is collected, and no withdrawal path — depositor or fee claim —
///         can take funds that active notes need.
contract SherwoodVault is Ownable {
    IERC20 public immutable token;

    uint256 public totalDeposits; // backer deposits + backer premiums, in token units
    uint256 public reserved; // sum of active note liabilities, in token units
    uint256 public bufferBps; // fraction of deposits kept unencumbered, e.g. 2000 = 20%

    address public noteContract;

    // ---------------------------------------------------------------- backers --
    // Deposits are pooled; each backer's claim is a share count. `totalDeposits`
    // rises with every premium (the backer share of it) and falls with every payout,
    // so a share's asset value is exactly how its holder earns premiums and bears
    // losses — no separate yield ledger to drift out of sync.
    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    // -------------------------------------------------------------- protocol --
    // Sherwood's cut of each premium, accrued to a bucket that is never part of
    // `totalDeposits`: it backs nothing, so claiming it can never strand a reserve.
    uint256 public protocolFeeBps; // e.g. 1000 = Sherwood keeps 10% of premiums
    address public treasury;
    uint256 public pendingProtocolFees;

    event Deposited(address indexed depositor, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event CapacityReserved(uint256 indexed noteId, address indexed payer, uint256 premium, uint256 liability);
    event CapacityReleased(uint256 indexed noteId, uint256 liability);
    event PayoutExecuted(uint256 indexed noteId, address indexed to, uint256 amount);
    event BufferChanged(uint256 bufferBps);
    event NoteContractSet(address indexed noteContract);
    event ProtocolFeeAccrued(uint256 indexed noteId, uint256 amount);
    event ProtocolFeesClaimed(address indexed to, uint256 amount);
    event FeeTermsChanged(uint256 protocolFeeBps, address treasury);

    error InsufficientCapacity();
    error InsufficientVaultBalance();
    error PayoutExceedsLiability();
    error NotNoteContract();
    error BufferTooHigh();
    error BufferBreachesReserves();
    error InvalidAmount();
    error TransferFailed();
    error EncumberedFunds();
    error AlreadySet();
    error InsufficientShares();
    error SharesTooSmall();
    error FeeTooHigh();
    error ZeroTreasury();

    uint256 public constant MAX_BUFFER_BPS = 5000;
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 2500;
    uint256 public constant BPS = 10_000;

    constructor(IERC20 _token, uint256 _bufferBps, uint256 _protocolFeeBps, address _treasury) {
        token = _token;
        _setBuffer(_bufferBps);
        _setFeeTerms(_protocolFeeBps, _treasury);
    }

    /// @notice Fund the vault with settlement token and mint backer shares at the
    ///         current exchange rate (1:1 into an empty vault). Premiums collected via
    ///         reserveFor raise `totalDeposits` without minting shares, so earlier
    ///         backers' shares earn the premiums; payouts shrink `totalDeposits` and
    ///         the same shares bear the losses.
    function deposit(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        // Rate read before any state change. A dust deposit that would mint zero
        // shares is refused rather than accepted as a silent donation.
        uint256 mint = totalDeposits == 0 ? amount : (amount * totalShares) / totalDeposits;
        if (mint == 0) revert SharesTooSmall();
        bool ok = token.transferFrom(msg.sender, address(this), amount);
        if (!ok) revert TransferFailed();
        totalDeposits += amount;
        sharesOf[msg.sender] += mint;
        totalShares += mint;
        emit Deposited(msg.sender, amount);
    }

    /// @notice Withdraw a chosen asset amount by burning the shares it costs. Capped at
    ///         `availableCapacity()`: the funds reserved for active notes, and the
    ///         unencumbered buffer behind them, are never withdrawable by anyone.
    ///         Winding the vault down is an explicit two-step — settle the notes,
    ///         `setBufferBps(0)`, then withdraw — for depositors exactly as it was
    ///         for the owner before them.
    ///
    ///         Share cost rounds UP against the caller (ceilDiv), so a withdrawal can
    ///         never pay out more than the requested assets; the pool keeps the dust.
    function withdraw(uint256 assets) external {
        if (assets == 0) revert InvalidAmount();
        if (assets > availableCapacity()) revert EncumberedFunds();
        uint256 burn = (assets * totalShares + totalDeposits - 1) / totalDeposits;
        if (burn > sharesOf[msg.sender]) revert InsufficientShares();

        sharesOf[msg.sender] -= burn;
        totalShares -= burn;
        totalDeposits -= assets;
        bool ok = token.transfer(msg.sender, assets);
        if (!ok) revert TransferFailed();
        emit Withdrawn(msg.sender, assets);
    }

    /// @notice Redeem shares for assets — the shares-denominated twin of `withdraw`.
    ///         Asset proceeds round DOWN against the caller; the pool keeps the dust.
    function redeem(uint256 shareAmount) external {
        if (shareAmount == 0) revert InvalidAmount();
        if (shareAmount > sharesOf[msg.sender]) revert InsufficientShares();
        uint256 assets = (shareAmount * totalDeposits) / totalShares;
        if (assets > availableCapacity()) revert EncumberedFunds();

        sharesOf[msg.sender] -= shareAmount;
        totalShares -= shareAmount;
        totalDeposits -= assets;
        bool ok = token.transfer(msg.sender, assets);
        if (!ok) revert TransferFailed();
        emit Withdrawn(msg.sender, assets);
    }

    /// @notice Reserve collateral for a new note and collect its premium, split into
    ///         the backer share (joins `totalDeposits`, backing future notes) and
    ///         Sherwood's fee share (parked outside the backing pool). Capacity is
    ///         checked before any token movement; if it fails the whole call reverts
    ///         with nothing collected. onlyNote because liability accounting must
    ///         stay in sync with note state.
    ///
    ///         The check is `premium + liability <= availableCapacity()`, evaluated on
    ///         pre-premium deposits; since only `backerCut <= premium` is added to
    ///         deposits afterwards, the post-state usable line sits at or above where
    ///         invariant 1 needs it — the fee slice can only ever make backing tighter,
    ///         never looser.
    ///
    ///         State is written before the token pull (checks-effects-interactions):
    ///         a settlement token with a transfer hook could otherwise re-enter and pass
    ///         the same capacity check twice, reserving twice against one balance.
    function reserveFor(uint256 noteId, address payer, uint256 premium, uint256 liability) external onlyNote {
        if (premium + liability > availableCapacity()) revert InsufficientCapacity();

        uint256 protocolCut = (premium * protocolFeeBps) / BPS;
        uint256 backerCut = premium - protocolCut;

        totalDeposits += backerCut;
        pendingProtocolFees += protocolCut;
        reserved += liability;

        if (premium > 0) {
            bool ok = token.transferFrom(payer, address(this), premium);
            if (!ok) revert TransferFailed();
        }

        emit CapacityReserved(noteId, payer, premium, liability);
        if (protocolCut > 0) emit ProtocolFeeAccrued(noteId, protocolCut);
    }

    /// @notice Settle a note: pay out to the recipient and release the reserved
    ///         liability. `payout <= liability` is guaranteed by ProtectionMath
    ///         (payout = floor - current <= floor = liability) and re-checked here.
    ///
    ///         Both effect writes land before the token transfer (checks-effects-
    ///         interactions), so a re-entrant settlement during the transfer can never
    ///         observe a reserve or deposit total that still counts this payout.
    function settlePayout(uint256 noteId, address recipient, uint256 liability, uint256 payout)
        external
        onlyNote
    {
        if (payout > liability) revert PayoutExceedsLiability();
        if (payout > token.balanceOf(address(this))) revert InsufficientVaultBalance();

        reserved -= liability;
        totalDeposits -= payout;

        if (payout > 0) {
            bool ok = token.transfer(recipient, payout);
            if (!ok) revert TransferFailed();
        }

        emit CapacityReleased(noteId, liability);
        if (payout > 0) emit PayoutExecuted(noteId, recipient, payout);
    }

    /// @notice Free capacity available for new liabilities.
    function availableCapacity() public view returns (uint256) {
        uint256 usable = totalDeposits - (totalDeposits * bufferBps) / BPS;
        return usable > reserved ? usable - reserved : 0;
    }

    /// @notice Sweep accrued protocol fees to the treasury. The fee bucket never
    ///         counted toward `totalDeposits`, so this cannot touch the funds backing
    ///         active notes — the physical-balance invariant
    ///         `balanceOf(this) >= totalDeposits + pendingProtocolFees` holds through
    ///         every path (deposit, reserveFor, settlePayout, sweep).
    function claimProtocolFees() external onlyOwner {
        uint256 amount = pendingProtocolFees;
        if (amount == 0) revert InvalidAmount();
        pendingProtocolFees = 0;
        bool ok = token.transfer(treasury, amount);
        if (!ok) revert TransferFailed();
        emit ProtocolFeesClaimed(treasury, amount);
    }

    /// @notice Set Sherwood's premium share (capped) and the fee destination.
    function setFeeTerms(uint256 newProtocolFeeBps, address newTreasury) external onlyOwner {
        _setFeeTerms(newProtocolFeeBps, newTreasury);
    }

    function setBufferBps(uint256 newBufferBps) external onlyOwner {
        _setBuffer(newBufferBps);
    }

    /// @notice Bind the note contract — once. The vault keeps one global `reserved`
    ///         ledger and trusts this address to move it honestly, so repointing
    ///         mid-life would strand every active note behind the old contract's
    ///         onlyNote gate (and hand whatever address is wired the reserve ledger).
    ///         Wiring happens exactly once at deploy; upgrades are full-stack
    ///         redeploys, never a pointer swap — the settlement token is immutable for
    ///         the same reason.
    function setNoteContract(address _noteContract) external onlyOwner {
        if (noteContract != address(0)) revert AlreadySet();
        if (_noteContract == address(0)) revert InvalidAmount();
        noteContract = _noteContract;
        emit NoteContractSet(_noteContract);
    }

    function _setFeeTerms(uint256 newProtocolFeeBps, address newTreasury) internal {
        if (newProtocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert FeeTooHigh();
        if (newTreasury == address(0)) revert ZeroTreasury();
        protocolFeeBps = newProtocolFeeBps;
        treasury = newTreasury;
        emit FeeTermsChanged(newProtocolFeeBps, newTreasury);
    }

    function _setBuffer(uint256 newBufferBps) internal {
        if (newBufferBps > MAX_BUFFER_BPS) revert BufferTooHigh();
        // Raising the buffer lowers the usable line, so a buffer that is fine for an
        // empty vault can strand collateral that was legitimately reserved under a
        // smaller one. Invariant 1 has to hold at all times, including immediately
        // after this call, so the raise is refused rather than allowed to breach it.
        // Lowering the buffer only ever raises the usable line and is always accepted.
        uint256 usable = totalDeposits - (totalDeposits * newBufferBps) / BPS;
        if (usable < reserved) revert BufferBreachesReserves();
        bufferBps = newBufferBps;
        emit BufferChanged(newBufferBps);
    }

    modifier onlyNote() {
        if (msg.sender != noteContract) revert NotNoteContract();
        _;
    }
}
