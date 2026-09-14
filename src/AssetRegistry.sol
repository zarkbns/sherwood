// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "./Ownable.sol";
import {ProtectionMath} from "./ProtectionMath.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";

/// @title AssetRegistry
/// @notice Registers supported stock tokens and their Chainlink price feeds.
///         Disabling an asset blocks new notes; existing notes still settle.
contract AssetRegistry is Ownable {
    struct Asset {
        string symbol;
        IAggregatorV3 feed;
        uint256 maxStaleness;
        bool active;
        bool registered;
    }

    mapping(address => Asset) private _assets;
    address[] private _assetList;

    event AssetRegistered(address indexed token, string symbol, address indexed feed, uint256 maxStaleness);
    event AssetStatusChanged(address indexed token, bool active);
    event AssetFeedUpdated(address indexed token, address indexed feed);

    error AlreadyRegistered();
    error NotRegistered();
    error ZeroAddress();
    error StalenessTooHigh();
    error UnsupportedFeedDecimals(uint8 feedDecimals);

    uint256 public constant MAX_STALENESS_CAP = 7 days;
    uint256 public constant DEFAULT_STALENESS = 72 hours;

    function registerAsset(address token, string calldata symbol, IAggregatorV3 feed, uint256 maxStaleness)
        external
        onlyOwner
    {
        if (token == address(0) || address(feed) == address(0)) revert ZeroAddress();
        if (maxStaleness > MAX_STALENESS_CAP) revert StalenessTooHigh();
        if (maxStaleness == 0) maxStaleness = DEFAULT_STALENESS;
        if (_assets[token].registered) revert AlreadyRegistered();
        _requirePriceDecimals(feed);

        _assets[token] = Asset({symbol: symbol, feed: feed, maxStaleness: maxStaleness, active: true, registered: true});
        _assetList.push(token);

        emit AssetRegistered(token, symbol, address(feed), maxStaleness);
    }

    function setAssetActive(address token, bool active) external onlyOwner {
        if (!_assets[token].registered) revert NotRegistered();
        _assets[token].active = active;
        emit AssetStatusChanged(token, active);
    }

    /// @notice Rotate an asset's feed (e.g. feed deprecation). Does not affect already-minted notes:
    ///         their entry price is frozen at creation and settlement re-reads the feed live.
    function setAssetFeed(address token, IAggregatorV3 feed) external onlyOwner {
        if (!_assets[token].registered) revert NotRegistered();
        if (address(feed) == address(0)) revert ZeroAddress();
        _requirePriceDecimals(feed);
        _assets[token].feed = feed;
        emit AssetFeedUpdated(token, address(feed));
    }

    /// @notice Rejects a feed whose answers are not at the 8-decimal scale every
    ///         ProtectionMath formula assumes. A 6-decimal feed would under-price a
    ///         position 100x and an 18-decimal feed would over-price it 1e10x, silently
    ///         and in the wrong direction for the buyer. Checked here rather than per
    ///         read because registration is a one-time owner action.
    function _requirePriceDecimals(IAggregatorV3 feed) internal view {
        uint8 feedDecimals = feed.decimals();
        if (feedDecimals != ProtectionMath.PRICE_DECIMALS) revert UnsupportedFeedDecimals(feedDecimals);
    }

    function getAsset(address token) external view returns (Asset memory) {
        return _assets[token];
    }

    function isSupported(address token) external view returns (bool) {
        return _assets[token].registered && _assets[token].active;
    }

    function allAssets() external view returns (address[] memory) {
        return _assetList;
    }
}
