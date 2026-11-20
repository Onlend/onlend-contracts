// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {PiecewiseLinearBorrowRate} from "src/pool/irm/libraries/borrow-rate/PiecewiseLinearBorrowRate.sol";

contract PiecewiseLinearBorrowRateFuzzTest is Test {
    // isValid()

    function testFuzz_isValid_ReturnsTrueForValidParams(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2
    ) public pure {
        (baseRate, optimalUtilisation, slope1, slope2) =
            _boundValidConfiguration(baseRate, optimalUtilisation, slope1, slope2);

        assertTrue(PiecewiseLinearBorrowRate.isValid(_params(baseRate, optimalUtilisation, slope1, slope2)));
    }

    function testFuzz_isValid_ReturnsFalseWhenOptimalUtilisationIsZero(uint256 baseRate, uint256 slope1, uint256 slope2)
        public
        pure
    {
        assertFalse(PiecewiseLinearBorrowRate.isValid(_params(baseRate, 0, slope1, slope2)));
    }

    function testFuzz_isValid_ReturnsFalseWhenOptimalUtilisationIsAtLeastOne(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2
    ) public pure {
        optimalUtilisation = bound(optimalUtilisation, MathUtils.ONE_18_DP, type(uint256).max);

        assertFalse(PiecewiseLinearBorrowRate.isValid(_params(baseRate, optimalUtilisation, slope1, slope2)));
    }

    function testFuzz_isValid_ReturnsFalseWhenBaseRateExceedsMaxBorrowRate(uint256 baseRate) public pure {
        baseRate = bound(baseRate, IRMConstants.MAX_BORROW_RATE + 1, type(uint256).max);

        assertFalse(PiecewiseLinearBorrowRate.isValid(_params(baseRate, 0.5e18, 0, 0)));
    }

    function testFuzz_isValid_ReturnsFalseWhenBaseRateAndSlope1ExceedMaxBorrowRate(uint256 baseRate, uint256 slope1)
        public
        pure
    {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        slope1 = bound(slope1, IRMConstants.MAX_BORROW_RATE - baseRate + 1, type(uint256).max - baseRate);

        assertFalse(PiecewiseLinearBorrowRate.isValid(_params(baseRate, 0.5e18, slope1, 0)));
    }

    function testFuzz_isValid_ReturnsFalseWhenTotalRateExceedsMaxBorrowRate(
        uint256 baseRate,
        uint256 slope1,
        uint256 slope2
    ) public pure {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        slope1 = bound(slope1, 0, IRMConstants.MAX_BORROW_RATE - baseRate);
        uint256 remainingRate = IRMConstants.MAX_BORROW_RATE - baseRate - slope1;
        slope2 = bound(slope2, remainingRate + 1, type(uint256).max - baseRate - slope1);

        assertFalse(PiecewiseLinearBorrowRate.isValid(_params(baseRate, 0.5e18, slope1, slope2)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsBelow128(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 0, 127);

        assertFalse(PiecewiseLinearBorrowRate.isValid(new bytes(paramsLength)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsAbove128(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 129, 1024);

        assertFalse(PiecewiseLinearBorrowRate.isValid(new bytes(paramsLength)));
    }

    // borrowRate()

    function testFuzz_borrowRate_ReturnsBaseRateWhenPoolHasNoLiquidity(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2
    ) public pure {
        (baseRate, optimalUtilisation, slope1, slope2) =
            _boundValidConfiguration(baseRate, optimalUtilisation, slope1, slope2);
        bytes memory params = _params(baseRate, optimalUtilisation, slope1, slope2);

        uint256 rate = PiecewiseLinearBorrowRate.borrowRate(params, 0, 0, 0);

        assertEq(rate, baseRate);
    }

    function testFuzz_borrowRate_ReturnsBaseRateWhenPoolHasNoDebt(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2,
        uint256 idleLiquidity
    ) public pure {
        (baseRate, optimalUtilisation, slope1, slope2) =
            _boundValidConfiguration(baseRate, optimalUtilisation, slope1, slope2);
        idleLiquidity = bound(idleLiquidity, 1, type(uint256).max);
        bytes memory params = _params(baseRate, optimalUtilisation, slope1, slope2);

        uint256 rate = PiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, 0, 0);

        assertEq(rate, baseRate);
    }

    function testFuzz_borrowRate_ReturnsBaseRateAndSlope1AtOptimalUtilisation(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2
    ) public pure {
        (baseRate, optimalUtilisation, slope1, slope2) =
            _boundValidConfiguration(baseRate, optimalUtilisation, slope1, slope2);
        bytes memory params = _params(baseRate, optimalUtilisation, slope1, slope2);

        uint256 rate = _borrowRateAtUtilisation(params, optimalUtilisation);

        assertEq(rate, baseRate + slope1);
    }

    function testFuzz_borrowRate_ReturnsMaxConfiguredRateAtFullUtilisation(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2,
        uint256 totalDebt
    ) public pure {
        (baseRate, optimalUtilisation, slope1, slope2) =
            _boundValidConfiguration(baseRate, optimalUtilisation, slope1, slope2);
        totalDebt = bound(totalDebt, 1, type(uint256).max);
        bytes memory params = _params(baseRate, optimalUtilisation, slope1, slope2);

        uint256 rate = PiecewiseLinearBorrowRate.borrowRate(params, 0, totalDebt, 0);

        assertEq(rate, baseRate + slope1 + slope2);
    }

    function testFuzz_borrowRate_StaysWithinFirstSlopeBelowOptimalUtilisation(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2,
        uint256 utilisation
    ) public pure {
        (baseRate, optimalUtilisation, slope1, slope2) =
            _boundValidConfiguration(baseRate, optimalUtilisation, slope1, slope2);
        utilisation = bound(utilisation, 0, optimalUtilisation - 1);
        bytes memory params = _params(baseRate, optimalUtilisation, slope1, slope2);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);

        assertGe(rate, baseRate);
        assertLe(rate, baseRate + slope1);
    }

    function testFuzz_borrowRate_StaysWithinSecondSlopeAboveOptimalUtilisation(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2,
        uint256 utilisation
    ) public pure {
        (baseRate, optimalUtilisation, slope1, slope2) =
            _boundValidConfiguration(baseRate, optimalUtilisation, slope1, slope2);
        utilisation = bound(utilisation, optimalUtilisation + 1, MathUtils.ONE_18_DP);
        bytes memory params = _params(baseRate, optimalUtilisation, slope1, slope2);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);

        assertGe(rate, baseRate + slope1);
        assertLe(rate, baseRate + slope1 + slope2);
    }

    function testFuzz_borrowRate_StaysWithinConfiguredRangeForAnyPoolSize(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2,
        uint256 totalLiquidity,
        uint256 totalDebt
    ) public pure {
        (baseRate, optimalUtilisation, slope1, slope2) =
            _boundValidConfiguration(baseRate, optimalUtilisation, slope1, slope2);
        totalDebt = bound(totalDebt, 0, totalLiquidity);
        uint256 idleLiquidity = totalLiquidity - totalDebt;
        bytes memory params = _params(baseRate, optimalUtilisation, slope1, slope2);

        uint256 rate = PiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, totalDebt, 0);

        assertGe(rate, baseRate);
        assertLe(rate, baseRate + slope1 + slope2);
    }

    function testFuzz_borrowRate_NeverDecreasesAsUtilisationIncreases(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2,
        uint256 utilisation,
        uint256 higherUtilisation
    ) public pure {
        (baseRate, optimalUtilisation, slope1, slope2) =
            _boundValidConfiguration(baseRate, optimalUtilisation, slope1, slope2);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP - 1);
        higherUtilisation = bound(higherUtilisation, utilisation + 1, MathUtils.ONE_18_DP);
        bytes memory params = _params(baseRate, optimalUtilisation, slope1, slope2);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);
        uint256 higherRate = _borrowRateAtUtilisation(params, higherUtilisation);

        assertGe(higherRate, rate);
    }

    function testFuzz_borrowRate_NeverDecreasesWhenDebtReplacesIdleLiquidity(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2,
        uint256 idleLiquidity,
        uint256 totalDebt,
        uint256 debtIncrease
    ) public pure {
        (baseRate, optimalUtilisation, slope1, slope2) =
            _boundValidConfiguration(baseRate, optimalUtilisation, slope1, slope2);
        idleLiquidity = bound(idleLiquidity, 1, type(uint256).max);
        totalDebt = bound(totalDebt, 0, type(uint256).max - idleLiquidity);
        debtIncrease = bound(debtIncrease, 1, idleLiquidity);
        bytes memory params = _params(baseRate, optimalUtilisation, slope1, slope2);

        uint256 rate = PiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, totalDebt, 0);
        uint256 higherRate =
            PiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity - debtIncrease, totalDebt + debtIncrease, 0);

        assertGe(higherRate, rate);
    }

    function testFuzz_borrowRate_ReturnsBaseRateWhenSlopesAreZero(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 utilisation
    ) public pure {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        optimalUtilisation = bound(optimalUtilisation, 1, MathUtils.ONE_18_DP - 1);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP);
        bytes memory params = _params(baseRate, optimalUtilisation, 0, 0);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);

        assertEq(rate, baseRate);
    }

    function testFuzz_borrowRate_ReturnsSameRateForDifferentTotalIrmDebt(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2,
        uint256 utilisation,
        uint256 totalIrmDebt
    ) public pure {
        (baseRate, optimalUtilisation, slope1, slope2) =
            _boundValidConfiguration(baseRate, optimalUtilisation, slope1, slope2);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP);
        totalIrmDebt = bound(totalIrmDebt, 1, type(uint256).max);
        bytes memory params = _params(baseRate, optimalUtilisation, slope1, slope2);
        uint256 idleLiquidity = MathUtils.ONE_18_DP - utilisation;

        uint256 rateWithoutIrmDebt = PiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, utilisation, 0);
        uint256 rateWithIrmDebt = PiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, utilisation, totalIrmDebt);

        assertEq(rateWithIrmDebt, rateWithoutIrmDebt);
    }

    function _boundValidConfiguration(uint256 baseRate, uint256 optimalUtilisation, uint256 slope1, uint256 slope2)
        private
        pure
        returns (uint256, uint256, uint256, uint256)
    {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        optimalUtilisation = bound(optimalUtilisation, 1, MathUtils.ONE_18_DP - 1);
        slope1 = bound(slope1, 0, IRMConstants.MAX_BORROW_RATE - baseRate);
        slope2 = bound(slope2, 0, IRMConstants.MAX_BORROW_RATE - baseRate - slope1);
        return (baseRate, optimalUtilisation, slope1, slope2);
    }

    /// @dev A total liquidity of 1e18 makes `totalDebt` numerically equal to the 18dp utilisation under test.
    function _borrowRateAtUtilisation(bytes memory params, uint256 utilisation) private pure returns (uint256) {
        return PiecewiseLinearBorrowRate.borrowRate(params, MathUtils.ONE_18_DP - utilisation, utilisation, 0);
    }

    function _params(uint256 baseRate, uint256 optimalUtilisation, uint256 slope1, uint256 slope2)
        private
        pure
        returns (bytes memory)
    {
        return abi.encode(baseRate, optimalUtilisation, slope1, slope2);
    }
}
