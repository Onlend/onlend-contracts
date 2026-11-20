// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {DoublePiecewiseLinearBorrowRate} from "src/pool/irm/libraries/borrow-rate/DoublePiecewiseLinearBorrowRate.sol";

contract DoublePiecewiseLinearBorrowRateUnitTest is Test {
    uint256 internal constant BASE_RATE = 0.1e18;
    uint256 internal constant UTILISATION_1 = 0.3e18;
    uint256 internal constant UTILISATION_2 = 0.7e18;
    uint256 internal constant SLOPE_1 = 0.2e18;
    uint256 internal constant SLOPE_2 = 0.2e18;
    uint256 internal constant SLOPE_3 = 0.2e18;

    // isValid()

    function test_isValid_ReturnsTrueForValidParams() public pure {
        assertTrue(
            DoublePiecewiseLinearBorrowRate.isValid(
                _params(BASE_RATE, UTILISATION_1, UTILISATION_2, SLOPE_1, SLOPE_2, SLOPE_3)
            )
        );
    }

    function test_isValid_ReturnsTrueForMinUtilisation1() public pure {
        assertTrue(
            DoublePiecewiseLinearBorrowRate.isValid(_params(BASE_RATE, 1, UTILISATION_2, SLOPE_1, SLOPE_2, SLOPE_3))
        );
    }

    function test_isValid_ReturnsTrueForAdjacentUtilisations() public pure {
        assertTrue(
            DoublePiecewiseLinearBorrowRate.isValid(
                _params(BASE_RATE, UTILISATION_1, UTILISATION_1 + 1, SLOPE_1, SLOPE_2, SLOPE_3)
            )
        );
    }

    function test_isValid_ReturnsTrueForMaxUtilisation2() public pure {
        assertTrue(
            DoublePiecewiseLinearBorrowRate.isValid(
                _params(BASE_RATE, UTILISATION_1, MathUtils.ONE_18_DP - 1, SLOPE_1, SLOPE_2, SLOPE_3)
            )
        );
    }

    function test_isValid_ReturnsTrueForMaxBorrowRate() public pure {
        assertTrue(
            DoublePiecewiseLinearBorrowRate.isValid(
                _params(
                    IRMConstants.MAX_BORROW_RATE - SLOPE_1 - SLOPE_2 - SLOPE_3,
                    UTILISATION_1,
                    UTILISATION_2,
                    SLOPE_1,
                    SLOPE_2,
                    SLOPE_3
                )
            )
        );
    }

    function test_isValid_ReturnsFalseWhenParamsAreEmpty() public pure {
        assertFalse(DoublePiecewiseLinearBorrowRate.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsBelow192() public pure {
        assertFalse(DoublePiecewiseLinearBorrowRate.isValid(new bytes(191)));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsAbove192() public pure {
        assertFalse(DoublePiecewiseLinearBorrowRate.isValid(new bytes(193)));
    }

    function test_isValid_ReturnsFalseWhenUtilisation1IsZero() public pure {
        assertFalse(
            DoublePiecewiseLinearBorrowRate.isValid(_params(BASE_RATE, 0, UTILISATION_2, SLOPE_1, SLOPE_2, SLOPE_3))
        );
    }

    function test_isValid_ReturnsFalseWhenUtilisationsAreEqual() public pure {
        assertFalse(
            DoublePiecewiseLinearBorrowRate.isValid(
                _params(BASE_RATE, UTILISATION_1, UTILISATION_1, SLOPE_1, SLOPE_2, SLOPE_3)
            )
        );
    }

    function test_isValid_ReturnsFalseWhenUtilisation1IsGreaterThanUtilisation2() public pure {
        assertFalse(
            DoublePiecewiseLinearBorrowRate.isValid(
                _params(BASE_RATE, UTILISATION_2, UTILISATION_1, SLOPE_1, SLOPE_2, SLOPE_3)
            )
        );
    }

    function test_isValid_ReturnsFalseWhenUtilisation2IsOne() public pure {
        assertFalse(
            DoublePiecewiseLinearBorrowRate.isValid(
                _params(BASE_RATE, UTILISATION_1, MathUtils.ONE_18_DP, SLOPE_1, SLOPE_2, SLOPE_3)
            )
        );
    }

    function test_isValid_ReturnsFalseWhenTotalRateExceedsMaxBorrowRate() public pure {
        assertFalse(
            DoublePiecewiseLinearBorrowRate.isValid(
                _params(
                    IRMConstants.MAX_BORROW_RATE - SLOPE_1 - SLOPE_2 - SLOPE_3 + 1,
                    UTILISATION_1,
                    UTILISATION_2,
                    SLOPE_1,
                    SLOPE_2,
                    SLOPE_3
                )
            )
        );
    }

    function test_isValid_ReturnsFalseWhenBaseRateAndSlope1ExceedMaxBorrowRate() public pure {
        assertFalse(
            DoublePiecewiseLinearBorrowRate.isValid(
                _params(IRMConstants.MAX_BORROW_RATE, UTILISATION_1, UTILISATION_2, 1, 0, 0)
            )
        );
    }

    function test_isValid_RevertsWhenBaseRateAndSlope1Overflow() public {
        vm.expectRevert(stdError.arithmeticError);
        this.isValid(_params(type(uint256).max, UTILISATION_1, UTILISATION_2, 1, 0, 0));
    }

    function test_isValid_RevertsWhenBaseRateAndFirstTwoSlopesOverflow() public {
        vm.expectRevert(stdError.arithmeticError);
        this.isValid(_params(type(uint256).max - 1, UTILISATION_1, UTILISATION_2, 1, 1, 0));
    }

    function test_isValid_RevertsWhenTotalRateOverflows() public {
        vm.expectRevert(stdError.arithmeticError);
        this.isValid(_params(type(uint256).max - 2, UTILISATION_1, UTILISATION_2, 1, 1, 1));
    }

    // borrowRate()

    function test_borrowRate_ReturnsBaseRateWhenPoolHasNoLiquidity() public pure {
        assertEq(DoublePiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 0, 0, 0), BASE_RATE);
    }

    function test_borrowRate_ReturnsBaseRateWhenPoolHasNoDebt() public pure {
        assertEq(DoublePiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 100e18, 0, 0), BASE_RATE);
    }

    function test_borrowRate_ReturnsFirstSlopeRateBelowUtilisation1() public pure {
        assertEq(DoublePiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 85e18, 15e18, 0), 0.2e18);
    }

    function test_borrowRate_ReturnsFirstSlopeRateAtUtilisation1() public pure {
        assertEq(DoublePiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 70e18, 30e18, 0), 0.3e18);
    }

    function test_borrowRate_ReturnsSecondSlopeRateBetweenUtilisations() public pure {
        assertEq(DoublePiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 50e18, 50e18, 0), 0.4e18);
    }

    function test_borrowRate_ReturnsSecondSlopeRateAtUtilisation2() public pure {
        assertEq(DoublePiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 30e18, 70e18, 0), 0.5e18);
    }

    function test_borrowRate_ReturnsThirdSlopeRateAboveUtilisation2() public pure {
        assertEq(DoublePiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 15e18, 85e18, 0), 0.6e18);
    }

    function test_borrowRate_ReturnsMaxConfiguredRateAtFullUtilisation() public pure {
        assertEq(DoublePiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 0, 100e18, 0), 0.7e18);
    }

    function test_borrowRate_TruncatesUtilisationOfIndivisiblePool() public pure {
        // slope1 == utilisation1 makes the first slope a 1:1 pass-through of utilisation.
        bytes memory params = _params(BASE_RATE, 0.5e18, UTILISATION_2, 0.5e18, SLOPE_2, SLOPE_3);

        uint256 rate = DoublePiecewiseLinearBorrowRate.borrowRate(params, 2, 1, 0);

        // 1 of 3 total liquidity is one-third utilisation, truncated to 333333333333333333 at 18dp.
        assertEq(rate, BASE_RATE + 333_333_333_333_333_333);
    }

    function test_borrowRate_ReturnsRoundedRateImmediatelyBelowUtilisation1() public pure {
        uint256 totalDebt = UTILISATION_1 - 1;
        uint256 idleLiquidity = MathUtils.ONE_18_DP - totalDebt;

        uint256 rate = DoublePiecewiseLinearBorrowRate.borrowRate(_defaultParams(), idleLiquidity, totalDebt, 0);

        // At utilisation1 - 1, the first-slope contribution is SLOPE_1 - 2/3 wei and rounds down to SLOPE_1 - 1 wei.
        assertEq(rate, BASE_RATE + SLOPE_1 - 1);
    }

    function test_borrowRate_ReturnsRoundedRateImmediatelyAboveUtilisation1() public pure {
        uint256 totalDebt = UTILISATION_1 + 1;
        uint256 idleLiquidity = MathUtils.ONE_18_DP - totalDebt;

        uint256 rate = DoublePiecewiseLinearBorrowRate.borrowRate(_defaultParams(), idleLiquidity, totalDebt, 0);

        // At utilisation1 + 1, the second-slope contribution is 0.5 wei and rounds down to zero.
        assertEq(rate, BASE_RATE + SLOPE_1);
    }

    function test_borrowRate_ReturnsRoundedRateImmediatelyBelowUtilisation2() public pure {
        uint256 totalDebt = UTILISATION_2 - 1;
        uint256 idleLiquidity = MathUtils.ONE_18_DP - totalDebt;

        uint256 rate = DoublePiecewiseLinearBorrowRate.borrowRate(_defaultParams(), idleLiquidity, totalDebt, 0);

        // At utilisation2 - 1, the second-slope contribution is SLOPE_2 - 0.5 wei and rounds down to SLOPE_2 - 1 wei.
        assertEq(rate, BASE_RATE + SLOPE_1 + SLOPE_2 - 1);
    }

    function test_borrowRate_ReturnsRoundedRateImmediatelyAboveUtilisation2() public pure {
        uint256 totalDebt = UTILISATION_2 + 1;
        uint256 idleLiquidity = MathUtils.ONE_18_DP - totalDebt;

        uint256 rate = DoublePiecewiseLinearBorrowRate.borrowRate(_defaultParams(), idleLiquidity, totalDebt, 0);

        // At utilisation2 + 1, the third-slope contribution is 2/3 wei and rounds down to zero.
        assertEq(rate, BASE_RATE + SLOPE_1 + SLOPE_2);
    }

    function test_borrowRate_RevertsWhenParamsCannotBeDecoded() public {
        vm.expectRevert();
        this.borrowRate("", 0, 0, 0);
    }

    function test_borrowRate_RevertsWhenTotalLiquidityOverflows() public {
        vm.expectRevert(stdError.arithmeticError);
        this.borrowRate(_defaultParams(), type(uint256).max, 1, 0);
    }

    function isValid(bytes memory params) external pure returns (bool) {
        return DoublePiecewiseLinearBorrowRate.isValid(params);
    }

    function borrowRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        pure
        returns (uint256)
    {
        return DoublePiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, totalDebt, totalIrmDebt);
    }

    function _defaultParams() private pure returns (bytes memory) {
        return _params(BASE_RATE, UTILISATION_1, UTILISATION_2, SLOPE_1, SLOPE_2, SLOPE_3);
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
