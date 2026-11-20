// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {FixedBorrowRate} from "src/pool/irm/libraries/borrow-rate/FixedBorrowRate.sol";

contract FixedBorrowRateFuzzTest is Test {
    // isValid()

    function testFuzz_isValid_ReturnsTrueWhenWithinBound(uint256 borrowRate) public pure {
        borrowRate = bound(borrowRate, 0, IRMConstants.MAX_BORROW_RATE);

        assertTrue(FixedBorrowRate.isValid(abi.encode(borrowRate)));
    }

    function testFuzz_isValid_ReturnsFalseWhenAboveBound(uint256 borrowRate) public pure {
        borrowRate = bound(borrowRate, IRMConstants.MAX_BORROW_RATE + 1, type(uint256).max);

        assertFalse(FixedBorrowRate.isValid(abi.encode(borrowRate)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsBelow32(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 0, 31);

        assertFalse(FixedBorrowRate.isValid(new bytes(paramsLength)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsAbove32(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 33, 1024);

        assertFalse(FixedBorrowRate.isValid(new bytes(paramsLength)));
    }

    // borrowRate()

    function testFuzz_borrowRate_ReturnsFixedRate(
        uint256 borrowRate,
        uint256 idleLiquidity,
        uint256 totalDebt,
        uint256 totalIrmDebt
    ) public pure {
        assertEq(FixedBorrowRate.borrowRate(abi.encode(borrowRate), idleLiquidity, totalDebt, totalIrmDebt), borrowRate);
    }
}
