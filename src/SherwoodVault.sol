// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "./interfaces/IERC20.sol";
import {Ownable} from "./Ownable.sol";

/// @title SherwoodVault
/// @notice Holds the settlement stablecoin, reserves collateral for active Protection
///         Notes, and executes payouts. The protocol never sells more protection than
///         it can cover: `reserveFor` reverts unless reserved + liability fits inside
///         deposits minus the reserve buffer, and the check always runs before any
///         premium is collected.
contract SherwoodVault is Ownable {
    IERC20 public immutable token;

    uint256 public totalDeposits; // deposits + collected premiums, in token units
    uint256 public reserved; // sum of active note liabilities, in token units
    uint256 public bufferBps; // fraction of deposits kept unencumbered, e.g. 2000 = 20%

    address public noteContract;

    event Deposited(address indexed depositor, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event CapacityReserved(uint256 indexed noteId, address indexed payer, uint256 premium, uint256 liability);
    event CapacityReleased(uint256 indexed noteId, uint256 liability);
    event PayoutExecuted(uint256 indexed noteId, address indexed to, uint256 amount);
    event BufferChanged(uint256 bufferBps);
    event NoteContractSet(address indexed noteContract);

    error InsufficientCapacity();
    error InsufficientVaultBalance();
    error PayoutExceedsLiability();
    error NotNoteContract();
    error BufferTooHigh();
    error InvalidAmount();
    error TransferFailed();
    error EncumberedFunds();

    uint256 public constant MAX_BUFFER_BPS = 5000;

    constructor(IERC20 _token, uint256 _bufferBps) {
        token = _token;
        _setBuffer(_bufferBps);
    }

    /// @notice Fund the vault with settlement token. Premiums collected via reserveFor
    ///         are also counted here, keeping `reserved <= free deposits` meaningful.
    function deposit(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        bool ok = token.transferFrom(msg.sender, address(this), amount);
        if (!ok) revert TransferFailed();
        totalDeposits += amount;
        emit Deposited(msg.sender, amount);
    }

    /// @notice Reserve collateral for a new note and collect its premium.
    ///         Capacity is checked before any token movement; if it fails the whole
    ///         call reverts with nothing collected. onlyNote because liability
    ///         accounting must stay in sync with note state.
    function reserveFor(uint256 noteId, address payer, uint256 premium, uint256 liability) external onlyNote {
        if (premium + liability > availableCapacity()) revert InsufficientCapacity();

        if (premium > 0) {
            bool ok = token.transferFrom(payer, address(this), premium);
            if (!ok) revert TransferFailed();
            totalDeposits += premium;
        }
        reserved += liability;

        emit CapacityReserved(noteId, payer, premium, liability);
    }

    /// @notice Settle a note: pay out to the recipient and release the reserved
    ///         liability. `payout <= liability` is guaranteed by ProtectionMath
    ///         (payout = floor - current <= floor = liability) and re-checked here.
    function settlePayout(uint256 noteId, address recipient, uint256 liability, uint256 payout)
        external
        onlyNote
    {
        if (payout > liability) revert PayoutExceedsLiability();
        if (payout > token.balanceOf(address(this))) revert InsufficientVaultBalance();

        reserved -= liability;
        if (payout > 0) {
            bool ok = token.transfer(recipient, payout);
            if (!ok) revert TransferFailed();
            totalDeposits -= payout;
        }

        emit CapacityReleased(noteId, liability);
        if (payout > 0) emit PayoutExecuted(noteId, recipient, payout);
    }

    /// @notice Free capacity available for new liabilities.
    function availableCapacity() public view returns (uint256) {
        uint256 usable = totalDeposits - (totalDeposits * bufferBps) / 10_000;
        return usable > reserved ? usable - reserved : 0;
    }

    function freeBalance() external view returns (uint256) {
        uint256 usable = totalDeposits - (totalDeposits * bufferBps) / 10_000;
        return usable > reserved ? usable - reserved : 0;
    }

    /// @notice Owner withdrawal of unencumbered, unreserved surplus only.
    function withdrawSurplus(address to, uint256 amount) external onlyOwner {
        if (amount > totalDeposits - reserved) revert EncumberedFunds();
        bool ok = token.transfer(to, amount);
        if (!ok) revert TransferFailed();
        totalDeposits -= amount;
        emit Withdrawn(to, amount);
    }

    function setBufferBps(uint256 newBufferBps) external onlyOwner {
        _setBuffer(newBufferBps);
    }

    function setNoteContract(address _noteContract) external onlyOwner {
        if (_noteContract == address(0)) revert InvalidAmount();
        noteContract = _noteContract;
        emit NoteContractSet(_noteContract);
    }

    function _setBuffer(uint256 newBufferBps) internal {
        if (newBufferBps > MAX_BUFFER_BPS) revert BufferTooHigh();
        bufferBps = newBufferBps;
        emit BufferChanged(newBufferBps);
    }

    modifier onlyNote() {
        if (msg.sender != noteContract) revert NotNoteContract();
        _;
    }
}
