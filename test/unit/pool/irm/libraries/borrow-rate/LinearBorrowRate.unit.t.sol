// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {LinearBorrowRate} from "src/pool/irm/libraries/borrow-rate/LinearBorrowRate.sol";

contract LinearBorrowRateUnitTest is Test {
    uint256 internal constant BASE_RATE = 0.1e18;
    uint256 internal constant SLOPE = 0.4e18;

    // isValid()

    function test_isValid_ReturnsTrueForValidParams() public pure {
        assertTrue(LinearBorrowRate.isValid(_params(BASE_RATE, SLOPE)));
    }

    function test_isValid_ReturnsTrueForMaxBorrowRate() public pure {
        assertTrue(LinearBorrowRate.isValid(_params(IRMConstants.MAX_BORROW_RATE - SLOPE, SLOPE)));
    }

    function test_isValid_ReturnsFalseWhenParamsAreEmpty() public pure {
        assertFalse(LinearBorrowRate.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsBelow64() public pure {
        assertFalse(LinearBorrowRate.isValid(new bytes(63)));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsAbove64() public pure {
        assertFalse(LinearBorrowRate.isValid(new bytes(65)));
    }

    function test_isValid_ReturnsFalseWhenTotalRateExceedsMaxBorrowRate() public pure {
        assertFalse(LinearBorrowRate.isValid(_params(IRMConstants.MAX_BORROW_RATE - SLOPE + 1, SLOPE)));
    }

    function test_isValid_RevertsWhenBorrowRatesOverflow() public {
        vm.expectRevert(stdError.arithmeticError);
        this.isValid(_params(type(uint256).max, 1));
    }

    // borrowRate()

    function test_borrowRate_ReturnsBaseRateWhenPoolHasNoLiquidity() public pure {
        assertEq(LinearBorrowRate.borrowRate(_defaultParams(), 0, 0, 0), BASE_RATE);
    }

    function test_borrowRate_ReturnsBaseRateWhenPoolHasNoDebt() public pure {
        assertEq(LinearBorrowRate.borrowRate(_defaultParams(), 100e18, 0, 0), BASE_RATE);
    }

    function test_borrowRate_ReturnsSlopeRateAtQuarterUtilisation() public pure {
        assertEq(LinearBorrowRate.borrowRate(_defaultParams(), 300e18, 100e18, 0), 0.2e18);
    }

    function test_borrowRate_ReturnsMaxConfiguredRateAtFullUtilisation() public pure {
        assertEq(LinearBorrowRate.borrowRate(_defaultParams(), 0, 100e18, 0), 0.5e18);
    }

    function test_borrowRate_TruncatesUtilisationOfIndivisiblePool() public pure {
        // A slope of one makes the slope a 1:1 pass-through of utilisation.
        bytes memory params = _params(BASE_RATE, MathUtils.ONE_18_DP);

        uint256 rate = LinearBorrowRate.borrowRate(params, 2, 1, 0);

        // 1 of 3 total liquidity is one-third utilisation, truncated to 333333333333333333 at 18dp.
        assertEq(rate, BASE_RATE + 333_333_333_333_333_333);
    }

    function test_borrowRate_TruncatesSlopeContribution() public pure {
        // 1 wei of utilisation with a 0.4 slope contributes 0.4 wei, which rounds down to zero.
        uint256 rate = LinearBorrowRate.borrowRate(_defaultParams(), MathUtils.ONE_18_DP - 1, 1, 0);

        assertEq(rate, BASE_RATE);
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
        return LinearBorrowRate.isValid(params);
    }

    function borrowRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        pure
        returns (uint256)
    {
        return LinearBorrowRate.borrowRate(params, idleLiquidity, totalDebt, totalIrmDebt);
    }

    function _defaultParams() private pure returns (bytes memory) {
        return _params(BASE_RATE, SLOPE);
    }

    function _params(uint256 baseRate, uint256 slope) private pure returns (bytes memory) {
        return abi.encode(baseRate, slope);
    }
}
