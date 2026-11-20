// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {PowerBorrowRate} from "src/pool/irm/libraries/borrow-rate/PowerBorrowRate.sol";

contract PowerBorrowRateUnitTest is Test {
    uint256 internal constant BASE_RATE = 0.1e18;
    uint256 internal constant SLOPE = 0.6e18;
    uint256 internal constant EXPONENT = 3;

    // isValid()

    function test_isValid_ReturnsTrueForValidParams() public pure {
        assertTrue(PowerBorrowRate.isValid(_params(BASE_RATE, SLOPE, EXPONENT)));
    }

    function test_isValid_ReturnsTrueWhenBaseRateIsZero() public pure {
        assertTrue(PowerBorrowRate.isValid(_params(0, SLOPE, EXPONENT)));
    }

    function test_isValid_ReturnsTrueWhenSlopeIsZero() public pure {
        assertTrue(PowerBorrowRate.isValid(_params(BASE_RATE, 0, EXPONENT)));
    }

    function test_isValid_ReturnsTrueForMinExponent() public pure {
        assertTrue(PowerBorrowRate.isValid(_params(BASE_RATE, SLOPE, 2)));
    }

    function test_isValid_ReturnsTrueForMaxExponent() public pure {
        assertTrue(PowerBorrowRate.isValid(_params(BASE_RATE, SLOPE, PowerBorrowRate.MAX_EXPONENT)));
    }

    function test_isValid_ReturnsTrueForMaxBorrowRate() public pure {
        assertTrue(PowerBorrowRate.isValid(_params(IRMConstants.MAX_BORROW_RATE - SLOPE, SLOPE, EXPONENT)));
    }

    function test_isValid_ReturnsFalseWhenParamsAreEmpty() public pure {
        assertFalse(PowerBorrowRate.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsBelow96() public pure {
        assertFalse(PowerBorrowRate.isValid(new bytes(95)));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsAbove96() public pure {
        assertFalse(PowerBorrowRate.isValid(new bytes(97)));
    }

    function test_isValid_ReturnsFalseWhenExponentIsZero() public pure {
        assertFalse(PowerBorrowRate.isValid(_params(BASE_RATE, SLOPE, 0)));
    }

    function test_isValid_ReturnsFalseWhenExponentIsOne() public pure {
        assertFalse(PowerBorrowRate.isValid(_params(BASE_RATE, SLOPE, 1)));
    }

    function test_isValid_ReturnsFalseWhenExponentExceedsMax() public pure {
        assertFalse(PowerBorrowRate.isValid(_params(BASE_RATE, SLOPE, PowerBorrowRate.MAX_EXPONENT + 1)));
    }

    function test_isValid_ReturnsFalseWhenTotalRateExceedsMaxBorrowRate() public pure {
        assertFalse(PowerBorrowRate.isValid(_params(IRMConstants.MAX_BORROW_RATE - SLOPE + 1, SLOPE, EXPONENT)));
    }

    function test_isValid_RevertsWhenBaseRateAndSlopeOverflow() public {
        vm.expectRevert(stdError.arithmeticError);
        this.isValid(_params(type(uint256).max, 1, EXPONENT));
    }

    // borrowRate()

    function test_borrowRate_ReturnsBaseRateWhenPoolHasNoLiquidity() public pure {
        assertEq(PowerBorrowRate.borrowRate(_defaultParams(), 0, 0, 0), BASE_RATE);
    }

    function test_borrowRate_ReturnsBaseRateWhenPoolHasNoDebt() public pure {
        assertEq(PowerBorrowRate.borrowRate(_defaultParams(), 100e18, 0, 0), BASE_RATE);
    }

    function test_borrowRate_ReturnsSquaredUtilisationRate() public pure {
        assertEq(PowerBorrowRate.borrowRate(_params(BASE_RATE, SLOPE, 2), 100e18, 100e18, 0), 0.25e18);
    }

    function test_borrowRate_ReturnsCubedUtilisationRate() public pure {
        assertEq(PowerBorrowRate.borrowRate(_defaultParams(), 100e18, 100e18, 0), 0.175e18);
    }

    function test_borrowRate_ReturnsPowerCurveRateForMaxExponent() public pure {
        uint256 rate =
            PowerBorrowRate.borrowRate(_params(BASE_RATE, SLOPE, PowerBorrowRate.MAX_EXPONENT), 100e18, 100e18, 0);

        // At 50% utilisation, utilisation^10 is 1/1024 and contributes 0.0005859375e18.
        assertEq(rate, 0.1005859375e18);
    }

    function test_borrowRate_ReturnsMaxConfiguredRateAtFullUtilisation() public pure {
        assertEq(PowerBorrowRate.borrowRate(_defaultParams(), 0, 100e18, 0), 0.7e18);
    }

    function test_borrowRate_TruncatesUtilisationOfIndivisiblePool() public pure {
        bytes memory params = _params(0, MathUtils.ONE_18_DP, 2);

        uint256 rate = PowerBorrowRate.borrowRate(params, 2, 1, 0);

        // One-third utilisation truncates to 333333333333333333 at 18dp; squaring it truncates to this value.
        assertEq(rate, 111_111_111_111_111_110);
    }

    function test_borrowRate_RoundsDownExponentiationImmediatelyBelowFullUtilisation() public pure {
        bytes memory params = _params(0, MathUtils.ONE_18_DP, 2);

        uint256 rate = PowerBorrowRate.borrowRate(params, 1, MathUtils.ONE_18_DP - 1, 0);

        // Squaring 1e18 - 1 produces 1e18 - 2 plus less than 1 wei, which rounds down.
        assertEq(rate, MathUtils.ONE_18_DP - 2);
    }

    function test_borrowRate_ReturnsBaseRateWhenExponentiationRoundsToZero() public pure {
        bytes memory params = _params(BASE_RATE, MathUtils.ONE_18_DP, 2);

        uint256 rate = PowerBorrowRate.borrowRate(params, MathUtils.ONE_18_DP - 1, 1, 0);

        // A utilisation of 1 at 18dp becomes less than 1 wei when squared and therefore rounds down to zero.
        assertEq(rate, BASE_RATE);
    }

    function test_borrowRate_RoundsDownSlopeContribution() public pure {
        bytes memory params = _params(BASE_RATE, 5, 2);

        uint256 rate = PowerBorrowRate.borrowRate(params, 1, 1, 0);

        // At 50% utilisation, the squared utilisation is 0.25e18 and contributes 1.25 wei, rounded down to 1 wei.
        assertEq(rate, BASE_RATE + 1);
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
        return PowerBorrowRate.isValid(params);
    }

    function borrowRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        pure
        returns (uint256)
    {
        return PowerBorrowRate.borrowRate(params, idleLiquidity, totalDebt, totalIrmDebt);
    }

    function _defaultParams() private pure returns (bytes memory) {
        return _params(BASE_RATE, SLOPE, EXPONENT);
    }

    function _params(uint256 baseRate, uint256 slope, uint256 exponent) private pure returns (bytes memory) {
        return abi.encode(baseRate, slope, exponent);
    }
}
