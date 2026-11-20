// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {UtilsLib} from "src/lib/UtilsLib.sol";

contract UtilsLibFuzzTest is Test {
    // exactlyOneZero()

    function testFuzz_exactlyOneZero_ReturnsTrueWhenOnlyFirstIsZero(uint256 y) public pure {
        y = bound(y, 1, type(uint256).max);

        assertTrue(UtilsLib.exactlyOneZero(0, y));
    }

    function testFuzz_exactlyOneZero_ReturnsTrueWhenOnlySecondIsZero(uint256 x) public pure {
        x = bound(x, 1, type(uint256).max);

        assertTrue(UtilsLib.exactlyOneZero(x, 0));
    }

    function testFuzz_exactlyOneZero_ReturnsFalseWhenNeitherIsZero(uint256 x, uint256 y) public pure {
        x = bound(x, 1, type(uint256).max);
        y = bound(y, 1, type(uint256).max);

        assertFalse(UtilsLib.exactlyOneZero(x, y));
    }

    /// @dev Swapping the arguments cannot change the answer, so neither argument carries a privileged role.
    function testFuzz_exactlyOneZero_IsSymmetric(uint256 x, uint256 y) public pure {
        assertEq(UtilsLib.exactlyOneZero(x, y), UtilsLib.exactlyOneZero(y, x));
    }
}
