// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {LinearBorrowRate} from "src/pool/irm/libraries/borrow-rate/LinearBorrowRate.sol";

contract LinearBorrowRateFuzzTest is Test {
    // isValid()

    function testFuzz_isValid_ReturnsTrueForValidParams(uint256 baseRate, uint256 slope) public pure {
        (baseRate, slope) = _boundValidConfiguration(baseRate, slope);

        assertTrue(LinearBorrowRate.isValid(_params(baseRate, slope)));
    }

    function testFuzz_isValid_ReturnsFalseWhenBaseRateExceedsMaxBorrowRate(uint256 baseRate) public pure {
        baseRate = bound(baseRate, IRMConstants.MAX_BORROW_RATE + 1, type(uint256).max);

        assertFalse(LinearBorrowRate.isValid(_params(baseRate, 0)));
    }

    function testFuzz_isValid_ReturnsFalseWhenTotalRateExceedsMaxBorrowRate(uint256 baseRate, uint256 slope)
        public
        pure
    {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        slope = bound(slope, IRMConstants.MAX_BORROW_RATE - baseRate + 1, type(uint256).max - baseRate);

        assertFalse(LinearBorrowRate.isValid(_params(baseRate, slope)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsBelow64(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 0, 63);

        assertFalse(LinearBorrowRate.isValid(new bytes(paramsLength)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsAbove64(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 65, 1024);

        assertFalse(LinearBorrowRate.isValid(new bytes(paramsLength)));
    }

    // borrowRate()

    function testFuzz_borrowRate_ReturnsBaseRateWhenPoolHasNoLiquidity(uint256 baseRate, uint256 slope) public pure {
        (baseRate, slope) = _boundValidConfiguration(baseRate, slope);

        uint256 rate = LinearBorrowRate.borrowRate(_params(baseRate, slope), 0, 0, 0);

        assertEq(rate, baseRate);
    }

    function testFuzz_borrowRate_ReturnsBaseRateWhenPoolHasNoDebt(
        uint256 baseRate,
        uint256 slope,
        uint256 idleLiquidity
    ) public pure {
        (baseRate, slope) = _boundValidConfiguration(baseRate, slope);
        idleLiquidity = bound(idleLiquidity, 1, type(uint256).max);

        uint256 rate = LinearBorrowRate.borrowRate(_params(baseRate, slope), idleLiquidity, 0, 0);

        assertEq(rate, baseRate);
    }

    function testFuzz_borrowRate_ReturnsMaxConfiguredRateAtFullUtilisation(
        uint256 baseRate,
        uint256 slope,
        uint256 totalDebt
    ) public pure {
        (baseRate, slope) = _boundValidConfiguration(baseRate, slope);
        totalDebt = bound(totalDebt, 1, type(uint256).max);

        uint256 rate = LinearBorrowRate.borrowRate(_params(baseRate, slope), 0, totalDebt, 0);

        assertEq(rate, baseRate + slope);
    }

    function testFuzz_borrowRate_StaysWithinConfiguredRangeForAnyPoolSize(
        uint256 baseRate,
        uint256 slope,
        uint256 totalLiquidity,
        uint256 totalDebt
    ) public pure {
        (baseRate, slope) = _boundValidConfiguration(baseRate, slope);
        totalDebt = bound(totalDebt, 0, totalLiquidity);
        uint256 idleLiquidity = totalLiquidity - totalDebt;

        uint256 rate = LinearBorrowRate.borrowRate(_params(baseRate, slope), idleLiquidity, totalDebt, 0);

        assertGe(rate, baseRate);
        assertLe(rate, baseRate + slope);
    }

    function testFuzz_borrowRate_NeverDecreasesAsUtilisationIncreases(
        uint256 baseRate,
        uint256 slope,
        uint256 utilisation,
        uint256 higherUtilisation
    ) public pure {
        (baseRate, slope) = _boundValidConfiguration(baseRate, slope);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP - 1);
        higherUtilisation = bound(higherUtilisation, utilisation + 1, MathUtils.ONE_18_DP);
        bytes memory params = _params(baseRate, slope);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);
        uint256 higherRate = _borrowRateAtUtilisation(params, higherUtilisation);

        assertGe(higherRate, rate);
    }

    function testFuzz_borrowRate_NeverDecreasesWhenDebtReplacesIdleLiquidity(
        uint256 baseRate,
        uint256 slope,
        uint256 idleLiquidity,
        uint256 totalDebt,
        uint256 debtIncrease
    ) public pure {
        (baseRate, slope) = _boundValidConfiguration(baseRate, slope);
        idleLiquidity = bound(idleLiquidity, 1, type(uint256).max);
        totalDebt = bound(totalDebt, 0, type(uint256).max - idleLiquidity);
        debtIncrease = bound(debtIncrease, 1, idleLiquidity);
        bytes memory params = _params(baseRate, slope);

        uint256 rate = LinearBorrowRate.borrowRate(params, idleLiquidity, totalDebt, 0);
        uint256 higherRate =
            LinearBorrowRate.borrowRate(params, idleLiquidity - debtIncrease, totalDebt + debtIncrease, 0);

        assertGe(higherRate, rate);
    }

    function testFuzz_borrowRate_ReturnsBaseRateWhenSlopeIsZero(uint256 baseRate, uint256 utilisation) public pure {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP);

        uint256 rate = _borrowRateAtUtilisation(_params(baseRate, 0), utilisation);

        assertEq(rate, baseRate);
    }

    function testFuzz_borrowRate_ReturnsSameRateForDifferentTotalIrmDebt(
        uint256 baseRate,
        uint256 slope,
        uint256 utilisation,
        uint256 totalIrmDebt
    ) public pure {
        (baseRate, slope) = _boundValidConfiguration(baseRate, slope);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP);
        totalIrmDebt = bound(totalIrmDebt, 1, type(uint256).max);
        bytes memory params = _params(baseRate, slope);
        uint256 idleLiquidity = MathUtils.ONE_18_DP - utilisation;

        uint256 rateWithoutIrmDebt = LinearBorrowRate.borrowRate(params, idleLiquidity, utilisation, 0);
        uint256 rateWithIrmDebt = LinearBorrowRate.borrowRate(params, idleLiquidity, utilisation, totalIrmDebt);

        assertEq(rateWithIrmDebt, rateWithoutIrmDebt);
    }

    function _boundValidConfiguration(uint256 baseRate, uint256 slope) private pure returns (uint256, uint256) {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        slope = bound(slope, 0, IRMConstants.MAX_BORROW_RATE - baseRate);
        return (baseRate, slope);
    }

    /// @dev A total liquidity of 1e18 makes `totalDebt` numerically equal to the 18dp utilisation under test.
    function _borrowRateAtUtilisation(bytes memory params, uint256 utilisation) private pure returns (uint256) {
        return LinearBorrowRate.borrowRate(params, MathUtils.ONE_18_DP - utilisation, utilisation, 0);
    }

    function _params(uint256 baseRate, uint256 slope) private pure returns (bytes memory) {
        return abi.encode(baseRate, slope);
    }
}
