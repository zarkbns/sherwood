// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ProtectionMath
/// @notice Pure math for Protection Notes. All USD arithmetic is 18 decimals.
///         Prices are Chainlink answers (8 decimals). Settlement-token conversion
///         happens only at the vault boundary via `toTokenUnits`.
library ProtectionMath {
    uint256 internal constant PRICE_PRECISION = 1e8;
    uint256 internal constant LEVEL_DENOMINATOR = 1e18;
    uint256 internal constant RATE_DENOMINATOR = 10_000;
    uint256 internal constant USD_PRECISION = 1e18;

    /// @notice Position value in USD-18: amount (token units, 18 dec) x price (8 dec) / 1e8.
    function usdValue(uint256 amount, uint256 price) internal pure returns (uint256) {
        return (amount * price) / PRICE_PRECISION;
    }

    /// @notice Floor value in USD-18: amount x entryPrice x level / 1e18 / 1e8.
    function protectedValue(uint256 amount, uint256 entryPrice, uint256 level) internal pure returns (uint256) {
        return ((amount * entryPrice * level) / LEVEL_DENOMINATOR) / PRICE_PRECISION;
    }

    /// @notice Settlement payout in USD-18: max(0, protected - current).
    function payout(uint256 amount, uint256 entryPrice, uint256 level, uint256 settlementPrice)
        internal
        pure
        returns (uint256)
    {
        uint256 floor = protectedValue(amount, entryPrice, level);
        uint256 current = usdValue(amount, settlementPrice);
        return floor > current ? floor - current : 0;
    }

    /// @notice Premium in USD-18 for a position value at rateBps.
    function premium(uint256 positionValue, uint256 rateBps) internal pure returns (uint256) {
        return (positionValue * rateBps) / RATE_DENOMINATOR;
    }

    /// @notice Full premium rate: base 1% + tier risk + duration risk.
    function premiumRateBps(uint256 level, uint256 duration) internal pure returns (uint256) {
        return 100 + tierBps(level) + durationBps(duration);
    }

    function tierBps(uint256 level) internal pure returns (uint256) {
        if (level == 70e16) return 100;
        if (level == 80e16) return 100;
        if (level == 90e16) return 200;
        revert InvalidLevel();
    }

    function durationBps(uint256 duration) internal pure returns (uint256) {
        if (duration == 7 days) return 50;
        if (duration == 14 days) return 75;
        if (duration == 30 days) return 100;
        revert InvalidDuration();
    }

    /// @notice Convert USD-18 amount to settlement-token units for a token with `decimals` <= 18.
    function toTokenUnits(uint256 usd18, uint8 decimals) internal pure returns (uint256) {
        if (decimals > 18) revert InvalidDecimals();
        return usd18 / (10 ** (18 - decimals));
    }

    error InvalidLevel();
    error InvalidDuration();
    error InvalidDecimals();
}
