// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {FixedBorrowRate} from "src/pool/irm/libraries/borrow-rate/FixedBorrowRate.sol";

contract FixedBorrowRateUnitTest is Test {
    uint256 internal constant BORROW_RATE = 0.05e18;

    // isValid()

    function test_isValid_ReturnsTrueForValidParams() public pure {
        assertTrue(FixedBorrowRate.isValid(abi.encode(BORROW_RATE)));
    }

    function test_isValid_ReturnsTrueForMaxBorrowRate() public pure {
        assertTrue(FixedBorrowRate.isValid(abi.encode(IRMConstants.MAX_BORROW_RATE)));
    }

    function test_isValid_ReturnsFalseWhenParamsAreEmpty() public pure {
        assertFalse(FixedBorrowRate.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsAbove32() public pure {
        assertFalse(FixedBorrowRate.isValid(new bytes(33)));
    }

    function test_isValid_ReturnsFalseWhenBorrowRateIsTooHigh() public pure {
        assertFalse(FixedBorrowRate.isValid(abi.encode(IRMConstants.MAX_BORROW_RATE + 1)));
    }

    // borrowRate()

    function test_borrowRate_ReturnsFixedRate() public pure {
        assertEq(FixedBorrowRate.borrowRate(abi.encode(BORROW_RATE), 0, 0, 0), BORROW_RATE);
    }

    function test_borrowRate_IgnoresMarketInputs() public pure {
        assertEq(FixedBorrowRate.borrowRate(abi.encode(BORROW_RATE), 100e18, 50e18, 25e18), BORROW_RATE);
    }

    function test_borrowRate_RevertsWhenParamsCannotBeDecoded() public {
        vm.expectRevert();
        this.borrowRate("");
    }

    function borrowRate(bytes memory params) external pure returns (uint256) {
        return FixedBorrowRate.borrowRate(params, 0, 0, 0);
    }
}
