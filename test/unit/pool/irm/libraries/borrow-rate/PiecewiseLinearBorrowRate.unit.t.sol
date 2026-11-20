// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {PiecewiseLinearBorrowRate} from "src/pool/irm/libraries/borrow-rate/PiecewiseLinearBorrowRate.sol";

contract PiecewiseLinearBorrowRateUnitTest is Test {
    uint256 internal constant BASE_RATE = 0.1e18;
    uint256 internal constant OPTIMAL_UTILISATION = 0.5e18;
    uint256 internal constant SLOPE_1 = 0.2e18;
    uint256 internal constant SLOPE_2 = 0.4e18;

    // isValid()

    function test_isValid_ReturnsTrueForValidParams() public pure {
        assertTrue(PiecewiseLinearBorrowRate.isValid(_params(BASE_RATE, OPTIMAL_UTILISATION, SLOPE_1, SLOPE_2)));
    }

    function test_isValid_ReturnsTrueForMinOptimalUtilisation() public pure {
        assertTrue(PiecewiseLinearBorrowRate.isValid(_params(BASE_RATE, 1, SLOPE_1, SLOPE_2)));
    }

    function test_isValid_ReturnsTrueForMaxOptimalUtilisation() public pure {
        assertTrue(PiecewiseLinearBorrowRate.isValid(_params(BASE_RATE, MathUtils.ONE_18_DP - 1, SLOPE_1, SLOPE_2)));
    }

    function test_isValid_ReturnsTrueForMaxBorrowRate() public pure {
        assertTrue(
            PiecewiseLinearBorrowRate.isValid(
                _params(IRMConstants.MAX_BORROW_RATE - SLOPE_1 - SLOPE_2, OPTIMAL_UTILISATION, SLOPE_1, SLOPE_2)
            )
        );
    }

    function test_isValid_ReturnsFalseWhenParamsAreEmpty() public pure {
        assertFalse(PiecewiseLinearBorrowRate.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsBelow128() public pure {
        assertFalse(PiecewiseLinearBorrowRate.isValid(new bytes(127)));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsAbove128() public pure {
        assertFalse(PiecewiseLinearBorrowRate.isValid(new bytes(129)));
    }

    function test_isValid_ReturnsFalseWhenOptimalUtilisationIsZero() public pure {
        assertFalse(PiecewiseLinearBorrowRate.isValid(_params(BASE_RATE, 0, SLOPE_1, SLOPE_2)));
    }

    function test_isValid_ReturnsFalseWhenOptimalUtilisationIsOne() public pure {
        assertFalse(PiecewiseLinearBorrowRate.isValid(_params(BASE_RATE, MathUtils.ONE_18_DP, SLOPE_1, SLOPE_2)));
    }

    function test_isValid_ReturnsFalseWhenTotalRateExceedsMaxBorrowRate() public pure {
        assertFalse(
            PiecewiseLinearBorrowRate.isValid(
                _params(IRMConstants.MAX_BORROW_RATE - SLOPE_1 - SLOPE_2 + 1, OPTIMAL_UTILISATION, SLOPE_1, SLOPE_2)
            )
        );
    }

    function test_isValid_ReturnsFalseWhenBaseRateAndSlope1ExceedMaxBorrowRate() public pure {
        assertFalse(PiecewiseLinearBorrowRate.isValid(_params(IRMConstants.MAX_BORROW_RATE, OPTIMAL_UTILISATION, 1, 0)));
    }

    function test_isValid_RevertsWhenBorrowRatesOverflow() public {
        vm.expectRevert(stdError.arithmeticError);
        this.isValid(_params(type(uint256).max, OPTIMAL_UTILISATION, 1, 0));
    }

    // borrowRate()

    function test_borrowRate_ReturnsBaseRateWhenPoolHasNoLiquidity() public pure {
        assertEq(PiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 0, 0, 0), BASE_RATE);
    }

    function test_borrowRate_ReturnsBaseRateWhenPoolHasNoDebt() public pure {
        assertEq(PiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 100e18, 0, 0), BASE_RATE);
    }

    function test_borrowRate_ReturnsFirstSlopeRateBelowOptimalUtilisation() public pure {
        assertEq(PiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 300e18, 100e18, 0), 0.2e18);
    }

    function test_borrowRate_ReturnsFirstSlopeRateAtOptimalUtilisation() public pure {
        assertEq(PiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 100e18, 100e18, 0), 0.3e18);
    }

    function test_borrowRate_ReturnsSecondSlopeRateAboveOptimalUtilisation() public pure {
        assertEq(PiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 100e18, 300e18, 0), 0.5e18);
    }

    function test_borrowRate_ReturnsMaxConfiguredRateAtFullUtilisation() public pure {
        assertEq(PiecewiseLinearBorrowRate.borrowRate(_defaultParams(), 0, 100e18, 0), 0.7e18);
    }

    function test_borrowRate_TruncatesUtilisationOfIndivisiblePool() public pure {
        // slope1 == optimalUtilisation makes the first slope a 1:1 pass-through of utilisation.
        bytes memory params = _params(BASE_RATE, OPTIMAL_UTILISATION, OPTIMAL_UTILISATION, SLOPE_2);

        uint256 rate = PiecewiseLinearBorrowRate.borrowRate(params, 2, 1, 0);

        // 1 of 3 total liquidity is one-third utilisation, truncated to 333333333333333333 at 18dp.
        assertEq(rate, BASE_RATE + 333_333_333_333_333_333);
    }

    function test_borrowRate_ReturnsRoundedRateImmediatelyBelowOptimalUtilisation() public pure {
        uint256 totalDebt = OPTIMAL_UTILISATION - 1;
        uint256 idleLiquidity = MathUtils.ONE_18_DP - totalDebt;

        uint256 rate = PiecewiseLinearBorrowRate.borrowRate(_defaultParams(), idleLiquidity, totalDebt, 0);

        // At optimal - 1, the first-slope contribution rounds from SLOPE_1 - 0.4 wei to SLOPE_1 - 1 wei.
        assertEq(rate, BASE_RATE + SLOPE_1 - 1);
    }

    function test_borrowRate_ReturnsRoundedRateImmediatelyAboveOptimalUtilisation() public pure {
        uint256 totalDebt = OPTIMAL_UTILISATION + 1;
        uint256 idleLiquidity = MathUtils.ONE_18_DP - totalDebt;

        uint256 rate = PiecewiseLinearBorrowRate.borrowRate(_defaultParams(), idleLiquidity, totalDebt, 0);

        // At optimal + 1, the second-slope contribution is 0.8 wei and rounds down to zero.
        assertEq(rate, BASE_RATE + SLOPE_1);
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
        return PiecewiseLinearBorrowRate.isValid(params);
    }

    function borrowRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        pure
        returns (uint256)
    {
        return PiecewiseLinearBorrowRate.borrowRate(params, idleLiquidity, totalDebt, totalIrmDebt);
    }

    function _defaultParams() private pure returns (bytes memory) {
        return _params(BASE_RATE, OPTIMAL_UTILISATION, SLOPE_1, SLOPE_2);
    }

    function _params(uint256 baseRate, uint256 optimalUtilisation, uint256 slope1, uint256 slope2)
        private
        pure
        returns (bytes memory)
    {
        return abi.encode(baseRate, optimalUtilisation, slope1, slope2);
    }
}
