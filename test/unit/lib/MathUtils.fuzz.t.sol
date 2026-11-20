// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";

contract MathUtilsFuzzTest is Test {
    // Bounds chosen so the largest intermediate power stays inside uint256: a base of at most 2 raised to at most 64
    // needs `2 ** 64 * 1e18`, about 1.8e37.
    uint256 constant MAX_BASE = 2e18;
    uint256 constant MAX_EXPONENT = 64;
    // Tests comparing consecutive exponents need the exact powers to separate by more than truncation can close, so
    // they start 1% above the scale rather than at it.
    uint256 constant MIN_GROWTH_BASE = 1.01e18;

    // exponentialBySquaring()

    function testFuzz_exponentialBySquaring_ReturnsScaleWhenExponentIsZero(uint256 x, uint256 scale) public pure {
        scale = bound(scale, 1, type(uint256).max);

        assertEq(MathUtils.exponentialBySquaring(x, 0, scale), scale);
    }

    function testFuzz_exponentialBySquaring_ReturnsBaseWhenExponentIsOne(uint256 x, uint256 scale) public pure {
        scale = bound(scale, 1, type(uint256).max);

        assertEq(MathUtils.exponentialBySquaring(x, 1, scale), x);
    }

    function testFuzz_exponentialBySquaring_ReturnsScaleWhenBaseEqualsScale(uint256 n, uint256 scale) public pure {
        scale = bound(scale, 1, type(uint256).max);

        assertEq(MathUtils.exponentialBySquaring(scale, n, scale), scale);
    }

    function testFuzz_exponentialBySquaring_ReturnsZeroWhenBaseIsZero(uint256 n, uint256 scale) public pure {
        n = bound(n, 1, type(uint256).max);
        scale = bound(scale, 1, type(uint256).max);

        assertEq(MathUtils.exponentialBySquaring(0, n, scale), 0);
    }

    function testFuzz_exponentialBySquaring_NeverBelowScaleWhenBaseIsAboveScale(uint256 x, uint256 n) public pure {
        x = bound(x, MathUtils.ONE_18_DP, MAX_BASE);
        n = bound(n, 0, MAX_EXPONENT);

        assertGe(MathUtils.exponentialBySquaring(x, n, MathUtils.ONE_18_DP), MathUtils.ONE_18_DP);
    }

    function testFuzz_exponentialBySquaring_NeverAboveScaleWhenBaseIsBelowScale(uint256 x, uint256 n) public pure {
        x = bound(x, 0, MathUtils.ONE_18_DP);
        n = bound(n, 0, MAX_EXPONENT);

        assertLe(MathUtils.exponentialBySquaring(x, n, MathUtils.ONE_18_DP), MathUtils.ONE_18_DP);
    }

    function testFuzz_exponentialBySquaring_NeverBelowBaseWhenBaseIsAboveScale(uint256 x, uint256 n) public pure {
        x = bound(x, MathUtils.ONE_18_DP, MAX_BASE);
        n = bound(n, 1, MAX_EXPONENT);

        assertGe(MathUtils.exponentialBySquaring(x, n, MathUtils.ONE_18_DP), x);
    }

    function testFuzz_exponentialBySquaring_NeverAboveBaseWhenBaseIsBelowScale(uint256 x, uint256 n) public pure {
        x = bound(x, 0, MathUtils.ONE_18_DP);
        n = bound(n, 1, MAX_EXPONENT);

        assertLe(MathUtils.exponentialBySquaring(x, n, MathUtils.ONE_18_DP), x);
    }

    function testFuzz_exponentialBySquaring_IncreasesWithBase(uint256 x, uint256 higherX, uint256 n) public pure {
        x = bound(x, 0, MAX_BASE);
        higherX = bound(higherX, x, MAX_BASE);
        n = bound(n, 0, MAX_EXPONENT);

        assertGe(
            MathUtils.exponentialBySquaring(higherX, n, MathUtils.ONE_18_DP),
            MathUtils.exponentialBySquaring(x, n, MathUtils.ONE_18_DP)
        );
    }

    function testFuzz_exponentialBySquaring_IncreasesWithExponentWhenBaseIsAboveScale(uint256 x, uint256 n)
        public
        pure
    {
        x = bound(x, MIN_GROWTH_BASE, MAX_BASE);
        n = bound(n, 0, MAX_EXPONENT - 1);

        assertGe(
            MathUtils.exponentialBySquaring(x, n + 1, MathUtils.ONE_18_DP),
            MathUtils.exponentialBySquaring(x, n, MathUtils.ONE_18_DP)
        );
    }
}
