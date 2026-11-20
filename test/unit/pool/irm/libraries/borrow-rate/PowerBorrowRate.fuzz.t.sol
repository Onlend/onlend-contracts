// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {PowerBorrowRate} from "src/pool/irm/libraries/borrow-rate/PowerBorrowRate.sol";

contract PowerBorrowRateFuzzTest is Test {
    // isValid()

    function testFuzz_isValid_ReturnsTrueForValidParams(uint256 baseRate, uint256 slope, uint256 exponent) public pure {
        (baseRate, slope, exponent) = _boundValidConfiguration(baseRate, slope, exponent);

        assertTrue(PowerBorrowRate.isValid(_params(baseRate, slope, exponent)));
    }

    function testFuzz_isValid_ReturnsFalseWhenExponentIsBelowMin(uint256 baseRate, uint256 slope, uint256 exponent)
        public
        pure
    {
        (baseRate, slope) = _boundValidRates(baseRate, slope);
        exponent = bound(exponent, 0, 1);

        assertFalse(PowerBorrowRate.isValid(_params(baseRate, slope, exponent)));
    }

    function testFuzz_isValid_ReturnsFalseWhenExponentExceedsMax(uint256 baseRate, uint256 slope, uint256 exponent)
        public
        pure
    {
        (baseRate, slope) = _boundValidRates(baseRate, slope);
        exponent = bound(exponent, PowerBorrowRate.MAX_EXPONENT + 1, type(uint256).max);

        assertFalse(PowerBorrowRate.isValid(_params(baseRate, slope, exponent)));
    }

    function testFuzz_isValid_ReturnsFalseWhenBaseRateExceedsMaxBorrowRate(uint256 baseRate) public pure {
        baseRate = bound(baseRate, IRMConstants.MAX_BORROW_RATE + 1, type(uint256).max);

        assertFalse(PowerBorrowRate.isValid(_params(baseRate, 0, 2)));
    }

    function testFuzz_isValid_ReturnsFalseWhenTotalRateExceedsMaxBorrowRate(
        uint256 baseRate,
        uint256 slope,
        uint256 exponent
    ) public pure {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        slope = bound(slope, IRMConstants.MAX_BORROW_RATE - baseRate + 1, type(uint256).max - baseRate);
        exponent = bound(exponent, 2, PowerBorrowRate.MAX_EXPONENT);

        assertFalse(PowerBorrowRate.isValid(_params(baseRate, slope, exponent)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsBelow96(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 0, 95);

        assertFalse(PowerBorrowRate.isValid(new bytes(paramsLength)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsAbove96(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 97, 1024);

        assertFalse(PowerBorrowRate.isValid(new bytes(paramsLength)));
    }

    // borrowRate()

    function testFuzz_borrowRate_ReturnsBaseRateWhenPoolHasNoLiquidity(
        uint256 baseRate,
        uint256 slope,
        uint256 exponent
    ) public pure {
        (baseRate, slope, exponent) = _boundValidConfiguration(baseRate, slope, exponent);
        bytes memory params = _params(baseRate, slope, exponent);

        uint256 rate = PowerBorrowRate.borrowRate(params, 0, 0, 0);

        assertEq(rate, baseRate);
    }

    function testFuzz_borrowRate_ReturnsBaseRateWhenPoolHasNoDebt(
        uint256 baseRate,
        uint256 slope,
        uint256 exponent,
        uint256 idleLiquidity
    ) public pure {
        (baseRate, slope, exponent) = _boundValidConfiguration(baseRate, slope, exponent);
        idleLiquidity = bound(idleLiquidity, 1, type(uint256).max);
        bytes memory params = _params(baseRate, slope, exponent);

        uint256 rate = PowerBorrowRate.borrowRate(params, idleLiquidity, 0, 0);

        assertEq(rate, baseRate);
    }

    function testFuzz_borrowRate_ReturnsMaxConfiguredRateAtFullUtilisation(
        uint256 baseRate,
        uint256 slope,
        uint256 exponent,
        uint256 totalDebt
    ) public pure {
        (baseRate, slope, exponent) = _boundValidConfiguration(baseRate, slope, exponent);
        totalDebt = bound(totalDebt, 1, type(uint256).max);
        bytes memory params = _params(baseRate, slope, exponent);

        uint256 rate = PowerBorrowRate.borrowRate(params, 0, totalDebt, 0);

        assertEq(rate, baseRate + slope);
    }

    function testFuzz_borrowRate_StaysWithinConfiguredRange(
        uint256 baseRate,
        uint256 slope,
        uint256 exponent,
        uint256 utilisation
    ) public pure {
        (baseRate, slope, exponent) = _boundValidConfiguration(baseRate, slope, exponent);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP);
        bytes memory params = _params(baseRate, slope, exponent);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);

        assertGe(rate, baseRate);
        assertLe(rate, baseRate + slope);
    }

    function testFuzz_borrowRate_StaysWithinConfiguredRangeForAnyPoolSize(
        uint256 baseRate,
        uint256 slope,
        uint256 exponent,
        uint256 totalLiquidity,
        uint256 totalDebt
    ) public pure {
        (baseRate, slope, exponent) = _boundValidConfiguration(baseRate, slope, exponent);
        totalDebt = bound(totalDebt, 0, totalLiquidity);
        uint256 idleLiquidity = totalLiquidity - totalDebt;
        bytes memory params = _params(baseRate, slope, exponent);

        uint256 rate = PowerBorrowRate.borrowRate(params, idleLiquidity, totalDebt, 0);

        assertGe(rate, baseRate);
        assertLe(rate, baseRate + slope);
    }

    function testFuzz_borrowRate_ReturnsSameRateWhenPoolIsScaled(
        uint256 baseRate,
        uint256 slope,
        uint256 exponent,
        uint256 totalLiquidity,
        uint256 totalDebt,
        uint256 scale
    ) public pure {
        (baseRate, slope, exponent) = _boundValidConfiguration(baseRate, slope, exponent);
        totalLiquidity = bound(totalLiquidity, 2, type(uint256).max / 2);
        totalDebt = bound(totalDebt, 1, totalLiquidity - 1);
        scale = bound(scale, 2, type(uint256).max / totalLiquidity);
        uint256 idleLiquidity = totalLiquidity - totalDebt;
        bytes memory params = _params(baseRate, slope, exponent);

        uint256 rate = PowerBorrowRate.borrowRate(params, idleLiquidity, totalDebt, 0);
        uint256 scaledRate = PowerBorrowRate.borrowRate(params, idleLiquidity * scale, totalDebt * scale, 0);

        assertEq(scaledRate, rate);
    }

    function testFuzz_borrowRate_NeverDecreasesAsUtilisationIncreases(
        uint256 baseRate,
        uint256 slope,
        uint256 exponent,
        uint256 utilisation,
        uint256 higherUtilisation
    ) public pure {
        (baseRate, slope, exponent) = _boundValidConfiguration(baseRate, slope, exponent);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP - 1);
        higherUtilisation = bound(higherUtilisation, utilisation + 1, MathUtils.ONE_18_DP);
        bytes memory params = _params(baseRate, slope, exponent);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);
        uint256 higherRate = _borrowRateAtUtilisation(params, higherUtilisation);

        assertGe(higherRate, rate);
    }

    function testFuzz_borrowRate_NeverDecreasesWhenDebtReplacesIdleLiquidity(
        uint256 baseRate,
        uint256 slope,
        uint256 exponent,
        uint256 idleLiquidity,
        uint256 totalDebt,
        uint256 debtIncrease
    ) public pure {
        (baseRate, slope, exponent) = _boundValidConfiguration(baseRate, slope, exponent);
        idleLiquidity = bound(idleLiquidity, 1, type(uint256).max);
        totalDebt = bound(totalDebt, 0, type(uint256).max - idleLiquidity);
        debtIncrease = bound(debtIncrease, 1, idleLiquidity);
        bytes memory params = _params(baseRate, slope, exponent);

        uint256 rate = PowerBorrowRate.borrowRate(params, idleLiquidity, totalDebt, 0);
        uint256 higherRate =
            PowerBorrowRate.borrowRate(params, idleLiquidity - debtIncrease, totalDebt + debtIncrease, 0);

        assertGe(higherRate, rate);
    }

    function testFuzz_borrowRate_NeverIncreasesAsExponentIncreases(
        uint256 baseRate,
        uint256 slope,
        uint256 lowerExponent,
        uint256 higherExponent,
        uint256 utilisation
    ) public pure {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE - 1);
        slope = bound(slope, 1, IRMConstants.MAX_BORROW_RATE - baseRate);
        lowerExponent = bound(lowerExponent, 2, PowerBorrowRate.MAX_EXPONENT - 1);
        higherExponent = bound(higherExponent, lowerExponent + 1, PowerBorrowRate.MAX_EXPONENT);
        utilisation = bound(utilisation, 1, MathUtils.ONE_18_DP - 1);
        bytes memory lowerParams = _params(baseRate, slope, lowerExponent);
        bytes memory higherParams = _params(baseRate, slope, higherExponent);

        uint256 lowerRate = _borrowRateAtUtilisation(lowerParams, utilisation);
        uint256 higherRate = _borrowRateAtUtilisation(higherParams, utilisation);

        assertLe(higherRate, lowerRate);
    }

    function testFuzz_borrowRate_ReturnsBaseRateWhenSlopeIsZero(uint256 baseRate, uint256 exponent, uint256 utilisation)
        public
        pure
    {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        exponent = bound(exponent, 2, PowerBorrowRate.MAX_EXPONENT);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP);
        bytes memory params = _params(baseRate, 0, exponent);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);

        assertEq(rate, baseRate);
    }

    function testFuzz_borrowRate_ReturnsSameRateForDifferentTotalIrmDebt(
        uint256 baseRate,
        uint256 slope,
        uint256 exponent,
        uint256 utilisation,
        uint256 totalIrmDebt
    ) public pure {
        (baseRate, slope, exponent) = _boundValidConfiguration(baseRate, slope, exponent);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP);
        totalIrmDebt = bound(totalIrmDebt, 1, type(uint256).max);
        bytes memory params = _params(baseRate, slope, exponent);
        uint256 idleLiquidity = MathUtils.ONE_18_DP - utilisation;

        uint256 rateWithoutIrmDebt = PowerBorrowRate.borrowRate(params, idleLiquidity, utilisation, 0);
        uint256 rateWithIrmDebt = PowerBorrowRate.borrowRate(params, idleLiquidity, utilisation, totalIrmDebt);

        assertEq(rateWithIrmDebt, rateWithoutIrmDebt);
    }

    function _boundValidConfiguration(uint256 baseRate, uint256 slope, uint256 exponent)
        private
        pure
        returns (uint256, uint256, uint256)
    {
        (baseRate, slope) = _boundValidRates(baseRate, slope);
        exponent = bound(exponent, 2, PowerBorrowRate.MAX_EXPONENT);
        return (baseRate, slope, exponent);
    }

    function _boundValidRates(uint256 baseRate, uint256 slope) private pure returns (uint256, uint256) {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        slope = bound(slope, 0, IRMConstants.MAX_BORROW_RATE - baseRate);
        return (baseRate, slope);
    }

    /// @dev A total liquidity of 1e18 makes `totalDebt` numerically equal to the 18dp utilisation under test.
    function _borrowRateAtUtilisation(bytes memory params, uint256 utilisation) private pure returns (uint256) {
        return PowerBorrowRate.borrowRate(params, MathUtils.ONE_18_DP - utilisation, utilisation, 0);
    }

    function _params(uint256 baseRate, uint256 slope, uint256 exponent) private pure returns (bytes memory) {
        return abi.encode(baseRate, slope, exponent);
    }
}
