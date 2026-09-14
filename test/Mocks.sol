// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../src/interfaces/IERC20.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {SherwoodVault} from "../src/SherwoodVault.sol";

/// @title Mocks
/// @notice Test doubles for the settlement token and the Chainlink feed. Kept
///         deliberately dumb.

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @dev `virtual` (and `public`, not `external`) so test/Reentrancy.t.sol can build a
    ///      hook-bearing settlement token on top of it and still reach the base logic,
    ///      the way an ERC777-style stablecoin could re-enter mid-transfer.
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        if (balanceOf[msg.sender] < amount) return false;
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        if (allowance[from][msg.sender] < amount) return false;
        if (balanceOf[from] < amount) return false;
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @dev Test-only: simulates an external drain of a holder's balance so the
    ///      vault's underfunded-settlement guard can be exercised.
    function drain(address from, address to, uint256 amount) external {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

/// @title MockUSDG
/// @notice Test double for the settlement token deployed on Robinhood Chain testnet at
///         0x8c4aa106a0A0d9ECAeD5C87e1AE766aa8Efbf006. Mirrors the source-verified
///         `src/mocks/MockUSDG.sol` exactly where Sherwood depends on it: 6 decimals,
///         symbol "USDG", `faucet()` paying FAUCET_AMOUNT per address per
///         FAUCET_COOLDOWN, and `mint`/`burn` closed to non-admins once `lockMint()` has
///         run. OpenZeppelin's ERC20 is replaced by this repo's minimal token so the
///         suite stays dependency-free — the events and reverts keep the same shapes.
contract MockUSDG is IERC20 {
    uint256 public constant FAUCET_AMOUNT = 1000e6;
    uint256 public constant FAUCET_COOLDOWN = 1 days;

    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public admin;
    bool public mintLocked;
    mapping(address => uint256) public lastFaucetAt;

    event Faucet(address indexed to, uint256 amount);
    event MintLocked(address indexed admin);

    error FaucetCooldown(uint256 nextAt);
    error NotAdmin();

    constructor() {
        name = "Mock USDG";
        symbol = "USDG";
        decimals = 6;
        admin = msg.sender;
    }

    /// @notice Public faucet: FAUCET_AMOUNT per address per FAUCET_COOLDOWN.
    function faucet() external {
        uint256 nextAt = lastFaucetAt[msg.sender] + FAUCET_COOLDOWN;
        if (block.timestamp < nextAt) revert FaucetCooldown(nextAt);
        lastFaucetAt[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
        emit Faucet(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Seconds until `account` may call `faucet()` again (0 = now).
    function faucetCooldownRemaining(address account) external view returns (uint256) {
        uint256 nextAt = lastFaucetAt[account] + FAUCET_COOLDOWN;
        return block.timestamp >= nextAt ? 0 : nextAt - block.timestamp;
    }

    function lockMint() external {
        if (msg.sender != admin) revert NotAdmin();
        mintLocked = true;
        emit MintLocked(msg.sender);
    }

    function mint(address to, uint256 amount) external {
        if (mintLocked && msg.sender != admin) revert NotAdmin();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (mintLocked && msg.sender != admin) revert NotAdmin();
        _burn(from, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (balanceOf[msg.sender] < amount) return false;
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] < amount) return false;
        if (balanceOf[from] < amount) return false;
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}

contract MockAggregator is IAggregatorV3 {
    int256 private _answer;
    uint256 private _updatedAt;
    uint80 private _roundId;
    uint80 private _answeredInRound;
    uint8 public decimals;

    constructor(uint8 _decimals) {
        decimals = _decimals;
        _roundId = 1;
        _answeredInRound = 1;
        _updatedAt = 1;
        _answer = 1;
    }

    function setPrice(int256 answer) external {
        _answer = answer;
        _roundId += 1;
        _answeredInRound = _roundId;
        _updatedAt = block.timestamp;
    }

    // Fault injection controls
    function setStaleRound() external {
        _answeredInRound = _roundId - 1;
    }

    function setUpdatedAt(uint256 ts) external {
        _updatedAt = ts;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }
}

/// @title MockSequencerFeed
/// @notice Test double for a Chainlink L2 sequencer uptime feed. Answer 0 = sequencer
///         up, 1 = down; `startedAt` carries when the sequencer last came back up, which
///         is what the oracle's post-restart grace period is measured against.
contract MockSequencerFeed is IAggregatorV3 {
    uint80 private _roundId = 1;
    int256 private _answer;
    uint256 private _startedAt;

    /// @dev Chainlink's uptime feeds report 0 decimals; the oracle never scales this feed.
    uint8 public constant decimals = 0;

    function setStatus(int256 answer, uint256 startedAt) external {
        _answer = answer;
        _startedAt = startedAt;
        _roundId += 1;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // Chainlink's uptime feed reports no useful update timestamp of its own; the
        // oracle reads only `answer` and `startedAt`, so both carry the restart time.
        return (_roundId, _answer, _startedAt, _startedAt, _roundId);
    }
}

/// @title HookedToken
/// @notice Settlement token with a one-shot external callback fired at the start of a
///         transfer, standing in for a token that re-enters its caller mid-move (ERC777
///         hooks, or a hostile stablecoin). The callback runs *before* the balance
///         update, which is the ordering a real hook hands an attacker.
contract HookedToken is MockERC20 {
    address public hookTarget;
    bytes public hookPayload;
    bool public hookOnTransfers = true;
    bool public hookOnTransferFroms = true;
    bool public swallowHookRevert;
    bool public fired;
    bytes public hookResult;

    error HookedCallFailed();

    constructor(uint8 decimals_) MockERC20("Hook", "HOOK", decimals_) {}

    /// @notice Arm the one-shot callback. With `swallow`, a reverting callback is
    ///         recorded instead of bubbled, so the outer call can be observed through to
    ///         completion.
    function arm(address target, bytes calldata payload, bool swallow) external {
        hookTarget = target;
        hookPayload = payload;
        swallowHookRevert = swallow;
        fired = false;
        delete hookResult;
    }

    /// @notice Choose which side of the token fires the callback.
    function setHookSides(bool onTransfer, bool onTransferFrom) external {
        hookOnTransfers = onTransfer;
        hookOnTransferFroms = onTransferFrom;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (hookOnTransfers) _fireHook();
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (hookOnTransferFroms) _fireHook();
        return super.transferFrom(from, to, amount);
    }

    function _fireHook() private {
        if (hookTarget == address(0) || fired) return;
        fired = true;
        (bool ok, bytes memory data) = hookTarget.call(hookPayload);
        if (ok) {
            hookResult = data;
        } else if (!swallowHookRevert) {
            revert HookedCallFailed();
        }
    }
}

/// @title VaultStateProbe
/// @notice Snapshots the vault's accounting at the moment it is called, so a test can
///         read the vault from inside an external token callback. The sentinels stay at
///         max() until the probe has actually run.
contract VaultStateProbe {
    SherwoodVault public immutable vault;
    uint256 public reservedAtCall = type(uint256).max;
    uint256 public depositsAtCall = type(uint256).max;
    uint256 public calls;

    constructor(SherwoodVault vault_) {
        vault = vault_;
    }

    function probe() external {
        reservedAtCall = vault.reserved();
        depositsAtCall = vault.totalDeposits();
        calls += 1;
    }
}
