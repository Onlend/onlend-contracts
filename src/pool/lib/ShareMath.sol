// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title  ShareMath
/// @notice Pure conversion formulae between a pool's underlying assets and the shares that claim them.
/// @dev    Conversions price against virtual assets and shares rather than the bare totals. The pair behaves as a
///         holder of `VIRTUAL_SHARES` backed by `VIRTUAL_ASSETS` that never deposits or redeems, holding the share
///         price near one while a pool is small and bounding what a conversion can round away. Interest accrues into
///         the asset base without issuing shares, so a deposit can otherwise come to be worth less than a single share
///         and round down to nothing, leaving its assets to the existing holders.
///
///         Once the share price falls below one, as when bad debt is socialised, the virtual holder claims less than
///         the `VIRTUAL_ASSETS` backing it and the real shares claim the rest, so they collectively claim more than the
///         pool holds, though by less than `VIRTUAL_ASSETS`. The last holders to exit can withdraw every remaining
///         asset but are left with shares that cannot be redeemed.
///
///         A falling share price lets each deposit mint more shares, so a pool repeatedly wiped out by bad debt would
///         grow its supply until conversions overflow. Deposits stop at `MAX_DEPOSIT_SHARES`, far below the
///         `MAX_TOTAL_SHARES` a conversion can price against, and the room between them is left to shares issued on
///         interest, which `sharesFit` keeps from crossing `MAX_TOTAL_SHARES`.
///
///         Callers pass the bases to price against, because a conversion does not always price against a pool's current
///         totals, and choose the rounding direction their accounting requires.
library ShareMath {
    using Math for uint256;

    /// @notice Virtual assets added to the asset base of every conversion.
    uint256 internal constant VIRTUAL_ASSETS = 1e6;
    /// @notice Virtual shares added to the share base of every conversion.
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    /// @notice Largest share base a conversion can price against without overflowing.
    uint256 internal constant MAX_TOTAL_SHARES = type(uint256).max - VIRTUAL_SHARES;
    /// @notice Share base past which deposits are not accepted, leaving the rest of `MAX_TOTAL_SHARES` to shares issued
    ///         on interest.
    uint256 internal constant MAX_DEPOSIT_SHARES = type(uint128).max;

    /// @notice Converts an asset amount into the shares it buys against a given share and asset base.
    /// @param  assets    Asset amount to convert.
    /// @param  supply    Shares the conversion prices against.
    /// @param  assetBase Assets the conversion prices against.
    /// @param  rounding  Direction to round the result.
    /// @return Shares `assets` buys against the given bases.
    function toShares(uint256 assets, uint256 supply, uint256 assetBase, Math.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        return assets.mulDiv(supply + VIRTUAL_SHARES, assetBase + VIRTUAL_ASSETS, rounding);
    }

    /// @notice Converts a share amount into the assets it claims against a given share and asset base.
    /// @param  shares    Share amount to convert.
    /// @param  supply    Shares the conversion prices against.
    /// @param  assetBase Assets the conversion prices against.
    /// @param  rounding  Direction to round the result.
    /// @return Assets `shares` claims against the given bases.
    function toAssets(uint256 shares, uint256 supply, uint256 assetBase, Math.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        return shares.mulDiv(assetBase + VIRTUAL_ASSETS, supply + VIRTUAL_SHARES, rounding);
    }

    /// @notice Returns whether the shares an asset amount buys, rounded down, keep a share base within
    ///         `MAX_TOTAL_SHARES`.
    /// @dev Compares the cross-multiplied sides in 512 bits rather than converting, as the conversion is what overflows
    ///      when the shares do not fit. Floored shares fit the room left under `MAX_TOTAL_SHARES` exactly when
    ///      `assets * (supply + VIRTUAL_SHARES) < (room + 1) * (assetBase + VIRTUAL_ASSETS)`.
    /// @param  assets    Asset amount to convert.
    /// @param  supply    Shares the conversion prices against, at most `MAX_TOTAL_SHARES`.
    /// @param  assetBase Assets the conversion prices against.
    /// @return True if `supply` plus the shares `assets` buys is at most `MAX_TOTAL_SHARES`.
    function sharesFit(uint256 assets, uint256 supply, uint256 assetBase) internal pure returns (bool) {
        (uint256 high, uint256 low) = Math.mul512(assets, supply + VIRTUAL_SHARES);
        (uint256 limitHigh, uint256 limitLow) = Math.mul512(MAX_TOTAL_SHARES - supply + 1, assetBase + VIRTUAL_ASSETS);

        return high < limitHigh || (high == limitHigh && low < limitLow);
    }
}
