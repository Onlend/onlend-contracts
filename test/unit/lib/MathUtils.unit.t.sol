// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {MathUtilsHarness} from "./mocks/MathUtilsHarness.sol";

contract MathUtilsUnitTest is Test {
    uint256 constant TWO_18_DP = 2e18;
    uint256 constant HALF_18_DP = 0.5e18;
    uint256 constant LARGE_BASE = 3e47;
    /// @dev `(2 ** 128) ** 2` is exactly `2 ** 256`
    uint256 constant FIRST_OVERFLOWING_BASE = 1 << 128;
    /// @dev `LARGEST_SQUARABLE_BASE = FIRST_OVERFLOWING_BASE - 1`
    uint256 constant LARGEST_SQUARABLE_BASE = type(uint128).max;

    MathUtilsHarness internal harness;

    function setUp() public {
        harness = new MathUtilsHarness();
    }

    // SECONDS_IN_YEAR

    function test_SECONDS_IN_YEAR_CountsThreeHundredAndSixtyFiveDays() public pure {
        assertEq(MathUtils.SECONDS_IN_YEAR, 31_536_000);
    }

    // ONE_4_DP

    function test_ONE_4_DP_IsOneAtFourDecimalPlaces() public pure {
        assertEq(MathUtils.ONE_4_DP, 10_000);
    }

    // ONE_18_DP

    function test_ONE_18_DP_IsOneAtEighteenDecimalPlaces() public pure {
        assertEq(MathUtils.ONE_18_DP, 1_000_000_000_000_000_000);
    }

    // exponentialBySquaring()

    function test_exponentialBySquaring_ReturnsScaleWhenExponentIsZero() public pure {
        assertEq(MathUtils.exponentialBySquaring(TWO_18_DP, 0, MathUtils.ONE_18_DP), MathUtils.ONE_18_DP);
    }

    function test_exponentialBySquaring_ReturnsBaseWhenExponentIsOne() public pure {
        assertEq(MathUtils.exponentialBySquaring(TWO_18_DP, 1, MathUtils.ONE_18_DP), TWO_18_DP);
    }

    function test_exponentialBySquaring_SquaresBase() public pure {
        assertEq(MathUtils.exponentialBySquaring(TWO_18_DP, 2, MathUtils.ONE_18_DP), 4e18);
    }

    function test_exponentialBySquaring_CubesBase() public pure {
        assertEq(MathUtils.exponentialBySquaring(TWO_18_DP, 3, MathUtils.ONE_18_DP), 8e18);
    }

    /// @dev Ten is `1010` in binary, so the result folds two of the squared bases together rather than returning a
    ///      single squaring: `2 ** 2` times `2 ** 8`.
    function test_exponentialBySquaring_RaisesToExponentWithMultipleSetBits() public pure {
        assertEq(MathUtils.exponentialBySquaring(TWO_18_DP, 10, MathUtils.ONE_18_DP), 1024e18);
    }

    /// @dev `1.1 ** 3` is `1.331`, which 18dp holds exactly.
    function test_exponentialBySquaring_RaisesFractionalBase() public pure {
        assertEq(MathUtils.exponentialBySquaring(1.1e18, 3, MathUtils.ONE_18_DP), 1.331e18);
    }

    function test_exponentialBySquaring_ReturnsScaleWhenBaseEqualsScale() public pure {
        assertEq(MathUtils.exponentialBySquaring(MathUtils.ONE_18_DP, 10, MathUtils.ONE_18_DP), MathUtils.ONE_18_DP);
    }

    function test_exponentialBySquaring_ReturnsZeroWhenBaseIsZero() public pure {
        assertEq(MathUtils.exponentialBySquaring(0, 3, MathUtils.ONE_18_DP), 0);
    }

    /// @dev Zero to the power of zero is the empty product, so the scale is returned rather than zero.
    function test_exponentialBySquaring_ReturnsScaleWhenBaseAndExponentAreZero() public pure {
        assertEq(MathUtils.exponentialBySquaring(0, 0, MathUtils.ONE_18_DP), MathUtils.ONE_18_DP);
    }

    function test_exponentialBySquaring_ShrinksBaseBelowScale() public pure {
        assertEq(MathUtils.exponentialBySquaring(HALF_18_DP, 3, MathUtils.ONE_18_DP), 0.125e18);
    }

    /// @dev `0.5 ** 64` is about `5.4e-20`, a twentieth of the smallest unit 18dp can hold, so nothing survives.
    function test_exponentialBySquaring_ReturnsZeroWhenPowerFallsBelowOneUnit() public pure {
        assertEq(MathUtils.exponentialBySquaring(HALF_18_DP, 64, MathUtils.ONE_18_DP), 0);
    }

    /// @dev The exact square of one unit above the scale is `1e18 + 2` plus a fraction of a unit, and the fraction
    ///      truncates away rather than carrying the result up to `1e18 + 3`.
    function test_exponentialBySquaring_RoundsDown() public pure {
        assertEq(
            MathUtils.exponentialBySquaring(MathUtils.ONE_18_DP + 1, 2, MathUtils.ONE_18_DP), MathUtils.ONE_18_DP + 2
        );
    }

    /// @dev `(3e47) ** 2 / 1e18` is `9e76`, well inside `uint256`.
    function test_exponentialBySquaring_SquaresLargeBase() public pure {
        assertEq(MathUtils.exponentialBySquaring(LARGE_BASE, 2, MathUtils.ONE_18_DP), 9e76);
    }

    /// @dev The boundary partner of the overflowing case. At a scale of one the power is a plain square, and
    ///      `(2 ** 128 - 1) ** 2` is `2 ** 256 - 2 ** 129 + 1` — the largest square a `uint256` holds.
    function test_exponentialBySquaring_ReturnsLargestPowerThatFits() public pure {
        assertEq(MathUtils.exponentialBySquaring(LARGEST_SQUARABLE_BASE, 2, 1), type(uint256).max - (1 << 129) + 2);
    }

    /// @dev Squaring `FIRST_OVERFLOWING_BASE` at a scale of one needs exactly `2 ** 256`, so it panics rather than
    ///      wrapping. Called through the harness because `vm.expectRevert` needs a call frame to observe.
    function test_exponentialBySquaring_RevertsWhenIntermediatePowerOverflows() public {
        vm.expectRevert(stdError.arithmeticError);
        harness.exponentialBySquaring(FIRST_OVERFLOWING_BASE, 2, 1);
    }
}
