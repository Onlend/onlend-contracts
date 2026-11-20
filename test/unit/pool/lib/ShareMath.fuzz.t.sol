// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";

import {ShareMath} from "src/pool/lib/ShareMath.sol";

contract ShareMathFuzzTest is Test {
    // Bounds chosen so a conversion stays within uint256 across the fuzzed bases.
    uint256 constant MAX_AMOUNT = type(uint128).max;
    uint256 constant MAX_SUPPLY = type(uint128).max;
    uint256 constant MAX_ASSET_BASE = type(uint128).max;

    // toShares()

    /// @dev The virtual amounts are equal, so an unpriced pool converts assets to shares one for one.
    function testFuzz_toShares_ConvertsOneToOneWhenBasesAreEmpty(uint256 assets) public pure {
        assets = bound(assets, 0, MAX_AMOUNT);

        assertEq(ShareMath.toShares(assets, 0, 0, Math.Rounding.Floor), assets);
    }

    function testFuzz_toShares_ConvertsNothingToNothing(uint256 supply, uint256 assetBase) public pure {
        supply = bound(supply, 0, MAX_SUPPLY);
        assetBase = bound(assetBase, 0, MAX_ASSET_BASE);

        assertEq(ShareMath.toShares(0, supply, assetBase, Math.Rounding.Floor), 0);
    }

    /// @dev Rounding can only ever move a conversion across a single share.
    function testFuzz_toShares_CeilExceedsFloorByAtMostOneShare(uint256 assets, uint256 supply, uint256 assetBase)
        public
        pure
    {
        assets = bound(assets, 0, MAX_AMOUNT);
        supply = bound(supply, 0, MAX_SUPPLY);
        assetBase = bound(assetBase, 0, MAX_ASSET_BASE);

        uint256 floored = ShareMath.toShares(assets, supply, assetBase, Math.Rounding.Floor);
        uint256 ceiled = ShareMath.toShares(assets, supply, assetBase, Math.Rounding.Ceil);

        assertGe(ceiled, floored);
        assertLe(ceiled - floored, 1);
    }

    function testFuzz_toShares_NeverBuysFewerSharesForMoreAssets(
        uint256 assets,
        uint256 extra,
        uint256 supply,
        uint256 assetBase
    ) public pure {
        assets = bound(assets, 0, MAX_AMOUNT);
        extra = bound(extra, 0, MAX_AMOUNT - assets);
        supply = bound(supply, 0, MAX_SUPPLY);
        assetBase = bound(assetBase, 0, MAX_ASSET_BASE);

        assertGe(
            ShareMath.toShares(assets + extra, supply, assetBase, Math.Rounding.Floor),
            ShareMath.toShares(assets, supply, assetBase, Math.Rounding.Floor)
        );
    }

    // toAssets()

    /// @dev The virtual amounts are equal, so an unpriced pool converts shares to assets one for one.
    function testFuzz_toAssets_ConvertsOneToOneWhenBasesAreEmpty(uint256 shares) public pure {
        shares = bound(shares, 0, MAX_AMOUNT);

        assertEq(ShareMath.toAssets(shares, 0, 0, Math.Rounding.Floor), shares);
    }

    function testFuzz_toAssets_ConvertsNothingToNothing(uint256 supply, uint256 assetBase) public pure {
        supply = bound(supply, 0, MAX_SUPPLY);
        assetBase = bound(assetBase, 0, MAX_ASSET_BASE);

        assertEq(ShareMath.toAssets(0, supply, assetBase, Math.Rounding.Floor), 0);
    }

    /// @dev Rounding can only ever move a conversion across a single asset.
    function testFuzz_toAssets_CeilExceedsFloorByAtMostOneAsset(uint256 shares, uint256 supply, uint256 assetBase)
        public
        pure
    {
        shares = bound(shares, 0, MAX_AMOUNT);
        supply = bound(supply, 0, MAX_SUPPLY);
        assetBase = bound(assetBase, 0, MAX_ASSET_BASE);

        uint256 floored = ShareMath.toAssets(shares, supply, assetBase, Math.Rounding.Floor);
        uint256 ceiled = ShareMath.toAssets(shares, supply, assetBase, Math.Rounding.Ceil);

        assertGe(ceiled, floored);
        assertLe(ceiled - floored, 1);
    }

    function testFuzz_toAssets_NeverClaimsFewerAssetsForMoreShares(
        uint256 shares,
        uint256 extra,
        uint256 supply,
        uint256 assetBase
    ) public pure {
        shares = bound(shares, 0, MAX_AMOUNT);
        extra = bound(extra, 0, MAX_AMOUNT - shares);
        supply = bound(supply, 0, MAX_SUPPLY);
        assetBase = bound(assetBase, 0, MAX_ASSET_BASE);

        assertGe(
            ShareMath.toAssets(shares + extra, supply, assetBase, Math.Rounding.Floor),
            ShareMath.toAssets(shares, supply, assetBase, Math.Rounding.Floor)
        );
    }

    // toShares() / toAssets()

    /// @dev Depositing and immediately redeeming must never return more than was paid in, however the bases are
    ///      priced — the rounding of a round trip always resolves against the account making it.
    function testFuzz_toAssets_RoundTripNeverReturnsMoreThanWasConverted(
        uint256 assets,
        uint256 supply,
        uint256 assetBase
    ) public pure {
        assets = bound(assets, 0, MAX_AMOUNT);
        supply = bound(supply, 0, MAX_SUPPLY);
        assetBase = bound(assetBase, 0, MAX_ASSET_BASE);

        uint256 shares = ShareMath.toShares(assets, supply, assetBase, Math.Rounding.Floor);

        assertLe(ShareMath.toAssets(shares, supply, assetBase, Math.Rounding.Floor), assets);
    }

    // sharesFit()

    /// @dev At a price of at least one asset per share, assets buy at most as many shares, so any amount within
    ///      the room left under `MAX_TOTAL_SHARES` fits.
    function testFuzz_sharesFit_ReturnsTrueWhenPriceIsAtLeastOneAndAssetsFitRoom(
        uint256 assets,
        uint256 supply,
        uint256 assetBase
    ) public pure {
        supply = bound(supply, 0, ShareMath.MAX_TOTAL_SHARES);
        assetBase = bound(assetBase, supply, type(uint256).max - ShareMath.VIRTUAL_ASSETS);
        assets = bound(assets, 0, ShareMath.MAX_TOTAL_SHARES - supply);

        assertTrue(ShareMath.sharesFit(assets, supply, assetBase));
    }

    /// @dev At a price of at most one asset per share, assets buy at least as many shares, so any amount beyond
    ///      the room left under `MAX_TOTAL_SHARES` does not fit.
    function testFuzz_sharesFit_ReturnsFalseWhenPriceIsAtMostOneAndAssetsExceedRoom(
        uint256 assets,
        uint256 supply,
        uint256 assetBase
    ) public pure {
        supply = bound(supply, 0, ShareMath.MAX_TOTAL_SHARES);
        assetBase = bound(assetBase, 0, supply);
        assets = bound(assets, ShareMath.MAX_TOTAL_SHARES - supply + 1, type(uint256).max);

        assertFalse(ShareMath.sharesFit(assets, supply, assetBase));
    }
}
