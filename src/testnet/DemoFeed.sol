// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";

/// @title DemoFeed
/// @notice TESTNET ONLY — NOT PART OF THE SHERWOOD PROTOCOL. Do not deploy to mainnet.
///         Chainlink publishes tokenized-equity feeds for Robinhood Chain mainnet only
///         (docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood). This stand-in
///         lets the testnet demo register assets and settle notes until real testnet
///         feeds exist. Prices are owner-set demo data: the protocol's oracle still
///         enforces freshness and sanity on everything it reads, but nothing this feed
///         reports is a market price. Wherever demo output is shown, disclose it.
contract DemoFeed is IAggregatorV3 {
    uint8 public immutable decimals;
    address public immutable owner;

    uint80 private _roundId;
    int256 private _answer;
    uint256 private _updatedAt;

    error NotOwner();
    error InvalidPrice();

    constructor(uint8 _decimals, int256 initialPrice) {
        if (initialPrice <= 0) revert InvalidPrice();
        decimals = _decimals;
        owner = msg.sender;
        _answer = initialPrice;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }

    function set(int256 price) external {
        if (msg.sender != owner) revert NotOwner();
        if (price <= 0) revert InvalidPrice();
        _answer = price;
        _roundId += 1;
        _updatedAt = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _roundId);
    }
}
