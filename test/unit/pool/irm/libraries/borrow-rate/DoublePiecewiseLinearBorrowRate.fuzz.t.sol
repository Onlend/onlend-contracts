// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {DoublePiecewiseLinearBorrowRate} from "src/pool/irm/libraries/borrow-rate/DoublePiecewiseLinearBorrowRate.sol";

contract DoublePiecewiseLinearBorrowRateFuzzTest is Test {
    // isValid()

    function testFuzz_isValid_ReturnsTrueForValidParams(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        assertTrue(
            DoublePiecewiseLinearBorrowRate.isValid(
                _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3)
            )
        );
    }

    function testFuzz_isValid_ReturnsFalseWhenUtilisation1IsZero(
        uint256 baseRate,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3
    ) public pure {
        assertFalse(DoublePiecewiseLinearBorrowRate.isValid(_params(baseRate, 0, utilisation2, slope1, slope2, slope3)));
    }

    function testFuzz_isValid_ReturnsFalseWhenUtilisationsAreEqual(
        uint256 baseRate,
        uint256 utilisation,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3
    ) public pure {
        utilisation = bound(utilisation, 1, type(uint256).max);

        assertFalse(
            DoublePiecewiseLinearBorrowRate.isValid(_params(baseRate, utilisation, utilisation, slope1, slope2, slope3))
        );
    }

    function testFuzz_isValid_ReturnsFalseWhenUtilisation1IsGreaterThanUtilisation2(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3
    ) public pure {
        utilisation2 = bound(utilisation2, 0, type(uint256).max - 1);
        utilisation1 = bound(utilisation1, utilisation2 + 1, type(uint256).max);

        assertFalse(
            DoublePiecewiseLinearBorrowRate.isValid(
                _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3)
            )
        );
    }

    function testFuzz_isValid_ReturnsFalseWhenUtilisation2IsAtLeastOne(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3
    ) public pure {
        utilisation2 = bound(utilisation2, MathUtils.ONE_18_DP, type(uint256).max);
        utilisation1 = bound(utilisation1, 1, utilisation2 - 1);

        assertFalse(
            DoublePiecewiseLinearBorrowRate.isValid(
                _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3)
            )
        );
    }

    function testFuzz_isValid_ReturnsFalseWhenBaseRateExceedsMaxBorrowRate(uint256 baseRate) public pure {
        baseRate = bound(baseRate, IRMConstants.MAX_BORROW_RATE + 1, type(uint256).max);

        assertFalse(DoublePiecewiseLinearBorrowRate.isValid(_params(baseRate, 0.3e18, 0.7e18, 0, 0, 0)));
    }

    function testFuzz_isValid_ReturnsFalseWhenBaseRateAndSlope1ExceedMaxBorrowRate(uint256 baseRate, uint256 slope1)
        public
        pure
    {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        slope1 = bound(slope1, IRMConstants.MAX_BORROW_RATE - baseRate + 1, type(uint256).max - baseRate);

        assertFalse(DoublePiecewiseLinearBorrowRate.isValid(_params(baseRate, 0.3e18, 0.7e18, slope1, 0, 0)));
    }

    function testFuzz_isValid_ReturnsFalseWhenBaseRateAndFirstTwoSlopesExceedMaxBorrowRate(
        uint256 baseRate,
        uint256 slope1,
        uint256 slope2
    ) public pure {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        slope1 = bound(slope1, 0, IRMConstants.MAX_BORROW_RATE - baseRate);
        uint256 remainingRate = IRMConstants.MAX_BORROW_RATE - baseRate - slope1;
        slope2 = bound(slope2, remainingRate + 1, type(uint256).max - baseRate - slope1);

        assertFalse(DoublePiecewiseLinearBorrowRate.isValid(_params(baseRate, 0.3e18, 0.7e18, slope1, slope2, 0)));
    }

    function testFuzz_isValid_ReturnsFalseWhenTotalRateExceedsMaxBorrowRate(
        uint256 baseRate,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3
    ) public pure {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        slope1 = bound(slope1, 0, IRMConstants.MAX_BORROW_RATE - baseRate);
        slope2 = bound(slope2, 0, IRMConstants.MAX_BORROW_RATE - baseRate - slope1);
        uint256 remainingRate = IRMConstants.MAX_BORROW_RATE - baseRate - slope1 - slope2;
        slope3 = bound(slope3, remainingRate + 1, type(uint256).max - baseRate - slope1 - slope2);

        assertFalse(DoublePiecewiseLinearBorrowRate.isValid(_params(baseRate, 0.3e18, 0.7e18, slope1, slope2, slope3)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsBelow192(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 0, 191);

        assertFalse(DoublePiecewiseLinearBorrowRate.isValid(new bytes(paramsLength)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsAbove192(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 193, 1024);

        assertFalse(DoublePiecewiseLinearBorrowRate.isValid(new bytes(paramsLength)));
    }

    // borrowRate()

    function testFuzz_borrowRate_ReturnsBaseRateWhenPoolHasNoLiquidity(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        uint256 rate = DoublePiecewiseLinearBorrowRate.borrowRate(params, 0, 0, 0);

        assertEq(rate, baseRate);
    }

    function testFuzz_borrowRate_ReturnsBaseRateWhenPoolHasNoDebt(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3,
        uint256 idleLiquidity
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        idleLiquidity = bound(idleLiquidity, 1, type(uint256).max);
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        uint256 rate = DoublePiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, 0, 0);

        assertEq(rate, baseRate);
    }

    function testFuzz_borrowRate_ReturnsBaseRateAndSlope1AtUtilisation1(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation1);

        assertEq(rate, baseRate + slope1);
    }

    function testFuzz_borrowRate_ReturnsBaseRateAndFirstTwoSlopesAtUtilisation2(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation2);

        assertEq(rate, baseRate + slope1 + slope2);
    }

    function testFuzz_borrowRate_ReturnsMaxConfiguredRateAtFullUtilisation(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3,
        uint256 totalDebt
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        totalDebt = bound(totalDebt, 1, type(uint256).max);
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        uint256 rate = DoublePiecewiseLinearBorrowRate.borrowRate(params, 0, totalDebt, 0);

        assertEq(rate, baseRate + slope1 + slope2 + slope3);
    }

    function testFuzz_borrowRate_StaysWithinFirstSlopeBelowUtilisation1(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3,
        uint256 utilisation
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        utilisation = bound(utilisation, 0, utilisation1 - 1);
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);

        assertGe(rate, baseRate);
        assertLe(rate, baseRate + slope1);
    }

    function testFuzz_borrowRate_StaysWithinSecondSlopeBetweenUtilisations(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3,
        uint256 utilisation
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        utilisation = bound(utilisation, utilisation1 + 1, utilisation2);
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);

        assertGe(rate, baseRate + slope1);
        assertLe(rate, baseRate + slope1 + slope2);
    }

    function testFuzz_borrowRate_StaysWithinThirdSlopeAboveUtilisation2(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3,
        uint256 utilisation
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        utilisation = bound(utilisation, utilisation2 + 1, MathUtils.ONE_18_DP);
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);

        assertGe(rate, baseRate + slope1 + slope2);
        assertLe(rate, baseRate + slope1 + slope2 + slope3);
    }

    function testFuzz_borrowRate_StaysWithinConfiguredRangeForAnyPoolSize(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3,
        uint256 totalLiquidity,
        uint256 totalDebt
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        totalDebt = bound(totalDebt, 0, totalLiquidity);
        uint256 idleLiquidity = totalLiquidity - totalDebt;
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        uint256 rate = DoublePiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, totalDebt, 0);

        assertGe(rate, baseRate);
        assertLe(rate, baseRate + slope1 + slope2 + slope3);
    }

    function testFuzz_borrowRate_ReturnsSameRateWhenPoolIsScaled(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3,
        uint256 totalLiquidity,
        uint256 totalDebt,
        uint256 scale
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        totalLiquidity = bound(totalLiquidity, 2, type(uint256).max / 2);
        totalDebt = bound(totalDebt, 1, totalLiquidity - 1);
        scale = bound(scale, 2, type(uint256).max / totalLiquidity);
        uint256 idleLiquidity = totalLiquidity - totalDebt;
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        uint256 rate = DoublePiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, totalDebt, 0);
        uint256 scaledRate =
            DoublePiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity * scale, totalDebt * scale, 0);

        assertEq(scaledRate, rate);
    }

    function testFuzz_borrowRate_NeverDecreasesAsUtilisationIncreases(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3,
        uint256 utilisation,
        uint256 higherUtilisation
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP - 1);
        higherUtilisation = bound(higherUtilisation, utilisation + 1, MathUtils.ONE_18_DP);
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);
        uint256 higherRate = _borrowRateAtUtilisation(params, higherUtilisation);

        assertGe(higherRate, rate);
    }

    function testFuzz_borrowRate_NeverDecreasesWhenDebtReplacesIdleLiquidity(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3,
        uint256 idleLiquidity,
        uint256 totalDebt,
        uint256 debtIncrease
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        idleLiquidity = bound(idleLiquidity, 1, type(uint256).max);
        totalDebt = bound(totalDebt, 0, type(uint256).max - idleLiquidity);
        debtIncrease = bound(debtIncrease, 1, idleLiquidity);
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);

        uint256 rate = DoublePiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, totalDebt, 0);
        uint256 higherRate = DoublePiecewiseLinearBorrowRate.borrowRate(
            params, idleLiquidity - debtIncrease, totalDebt + debtIncrease, 0
        );

        assertGe(higherRate, rate);
    }

    function testFuzz_borrowRate_ReturnsBaseRateWhenSlopesAreZero(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 utilisation
    ) public pure {
        baseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        utilisation1 = bound(utilisation1, 1, MathUtils.ONE_18_DP - 2);
        utilisation2 = bound(utilisation2, utilisation1 + 1, MathUtils.ONE_18_DP - 1);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP);
        bytes memory params = _params(baseRate, utilisation1, utilisation2, 0, 0, 0);

        uint256 rate = _borrowRateAtUtilisation(params, utilisation);

        assertEq(rate, baseRate);
    }

    function testFuzz_borrowRate_ReturnsSameRateForDifferentTotalIrmDebt(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3,
        uint256 utilisation,
        uint256 totalIrmDebt
    ) public pure {
        (baseRate, utilisation1, utilisation2, slope1, slope2, slope3) =
            _boundValidConfiguration(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP);
        totalIrmDebt = bound(totalIrmDebt, 1, type(uint256).max);
        bytes memory params = _params(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
        uint256 idleLiquidity = MathUtils.ONE_18_DP - utilisation;

        uint256 rateWithoutIrmDebt = DoublePiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, utilisation, 0);
        uint256 rateWithIrmDebt =
            DoublePiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, utilisation, totalIrmDebt);

        assertEq(rateWithIrmDebt, rateWithoutIrmDebt);
    }

    function _boundValidConfiguration(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3
    )
        private
        pure
        returns (
            uint256 boundedBaseRate,
            uint256 boundedUtilisation1,
            uint256 boundedUtilisation2,
            uint256 boundedSlope1,
            uint256 boundedSlope2,
            uint256 boundedSlope3
        )
    {
        boundedBaseRate = bound(baseRate, 0, IRMConstants.MAX_BORROW_RATE);
        boundedUtilisation1 = bound(utilisation1, 1, MathUtils.ONE_18_DP - 2);
        boundedUtilisation2 = bound(utilisation2, boundedUtilisation1 + 1, MathUtils.ONE_18_DP - 1);
        boundedSlope1 = bound(slope1, 0, IRMConstants.MAX_BORROW_RATE - boundedBaseRate);
        boundedSlope2 = bound(slope2, 0, IRMConstants.MAX_BORROW_RATE - boundedBaseRate - boundedSlope1);
        boundedSlope3 = bound(slope3, 0, IRMConstants.MAX_BORROW_RATE - boundedBaseRate - boundedSlope1 - boundedSlope2);
    }

    /// @dev A total liquidity of 1e18 makes `totalDebt` numerically equal to the 18dp utilisation under test.
    function _borrowRateAtUtilisation(bytes memory params, uint256 utilisation) private pure returns (uint256) {
        return DoublePiecewiseLinearBorrowRate.borrowRate(params, MathUtils.ONE_18_DP - utilisation, utilisation, 0);
    }

    function _params(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3
    ) private pure returns (bytes memory) {
        return abi.encode(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
    }
}
