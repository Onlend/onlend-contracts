// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {UtilsLib} from "src/lib/UtilsLib.sol";

contract UtilsLibUnitTest is Test {
    uint256 constant AMOUNT = 1000e18;

    // exactlyOneZero()

    function test_exactlyOneZero_ReturnsTrueWhenOnlyFirstIsZero() public pure {
        assertTrue(UtilsLib.exactlyOneZero(0, AMOUNT));
    }

    function test_exactlyOneZero_ReturnsTrueWhenOnlySecondIsZero() public pure {
        assertTrue(UtilsLib.exactlyOneZero(AMOUNT, 0));
    }

    function test_exactlyOneZero_ReturnsFalseWhenBothAreZero() public pure {
        assertFalse(UtilsLib.exactlyOneZero(0, 0));
    }

    function test_exactlyOneZero_ReturnsFalseWhenNeitherIsZero() public pure {
        assertFalse(UtilsLib.exactlyOneZero(AMOUNT, AMOUNT));
    }
}
