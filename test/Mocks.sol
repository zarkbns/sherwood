// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../src/interfaces/IERC20.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";

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

    /// @dev Test-only: simulates an external drain of a holder's balance so the
    ///      vault's underfunded-settlement guard can be exercised.
    function drain(address from, address to, uint256 amount) external {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
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
