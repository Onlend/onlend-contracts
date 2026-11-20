// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";

import {ShareMath} from "src/pool/lib/ShareMath.sol";

contract ShareMathUnitTest is Test {
    // Bases the virtual pair prices at exactly two assets per share: 1,000,000 shares against 3,000,000 assets
    // becomes 2,000,000 against 4,000,000.
    uint256 constant SUPPLY = 1e6;
    uint256 constant ASSET_BASE = 3e6;
    // Bases the virtual pair prices at exactly one and a half assets per share: 1,000,000 shares against 2,000,000
    // assets becomes 2,000,000 against 3,000,000.
    uint256 constant HALF_STEP_SUPPLY = 1e6;
    uint256 constant HALF_STEP_ASSET_BASE = 2e6;

    // toShares()

    function test_toShares_ConvertsOneToOneWhenBasesAreEmpty() public pure {
        assertEq(ShareMath.toShares(1e6, 0, 0, Math.Rounding.Floor), 1e6);
    }

    function test_toShares_PricesAgainstTheGivenBases() public pure {
        assertEq(ShareMath.toShares(200, SUPPLY, ASSET_BASE, Math.Rounding.Floor), 100);
    }

    /// @dev 5 assets at two assets per share is 2.5 shares.
    function test_toShares_RoundsDownWhenFloored() public pure {
        assertEq(ShareMath.toShares(5, SUPPLY, ASSET_BASE, Math.Rounding.Floor), 2);
    }

    function test_toShares_RoundsUpWhenCeiled() public pure {
        assertEq(ShareMath.toShares(5, SUPPLY, ASSET_BASE, Math.Rounding.Ceil), 3);
    }

    // toAssets()

    function test_toAssets_ConvertsOneToOneWhenBasesAreEmpty() public pure {
        assertEq(ShareMath.toAssets(1e6, 0, 0, Math.Rounding.Floor), 1e6);
    }

    function test_toAssets_PricesAgainstTheGivenBases() public pure {
        assertEq(ShareMath.toAssets(100, SUPPLY, ASSET_BASE, Math.Rounding.Floor), 200);
    }

    /// @dev 5 shares at one and a half assets per share is 7.5 assets.
    function test_toAssets_RoundsDownWhenFloored() public pure {
        assertEq(ShareMath.toAssets(5, HALF_STEP_SUPPLY, HALF_STEP_ASSET_BASE, Math.Rounding.Floor), 7);
    }

    function test_toAssets_RoundsUpWhenCeiled() public pure {
        assertEq(ShareMath.toAssets(5, HALF_STEP_SUPPLY, HALF_STEP_ASSET_BASE, Math.Rounding.Ceil), 8);
    }

    // sharesFit()

    /// @dev Equal bases price one asset at exactly one share.
    function test_sharesFit_ReturnsTrueWhenSharesReachMaxTotalShares() public pure {
        assertTrue(ShareMath.sharesFit(ShareMath.MAX_TOTAL_SHARES - SUPPLY, SUPPLY, SUPPLY));
    }

    /// @dev Equal bases price one asset at exactly one share.
    function test_sharesFit_ReturnsFalseWhenSharesExceedMaxTotalSharesByOne() public pure {
        assertFalse(ShareMath.sharesFit(ShareMath.MAX_TOTAL_SHARES - SUPPLY + 1, SUPPLY, SUPPLY));
    }

    /// @dev With no asset base each asset buys far more than one share, so `toShares` itself would overflow.
    function test_sharesFit_ReturnsFalseWhenConversionWouldOverflow() public pure {
        assertFalse(ShareMath.sharesFit(type(uint256).max, ShareMath.MAX_TOTAL_SHARES - 1, 0));
    }
}
