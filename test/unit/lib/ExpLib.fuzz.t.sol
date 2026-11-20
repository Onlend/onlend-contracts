// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ExpLib} from "src/lib/ExpLib.sol";

contract ExpLibFuzzTest is Test {
    // wExp()

    function testFuzz_wExp_ReturnsZeroBelowLowerBound(int256 x) public pure {
        x = bound(x, type(int256).min, ExpLib.LN_WEI_INT - 1);

        assertEq(ExpLib.wExp(x), 0);
    }

    function testFuzz_wExp_ReturnsUpperValueAtOrAboveUpperBound(int256 x) public pure {
        x = bound(x, ExpLib.WEXP_UPPER_BOUND, type(int256).max);

        assertEq(ExpLib.wExp(x), ExpLib.WEXP_UPPER_VALUE);
    }

    function testFuzz_wExp_DoublesWhenExponentIncreasesByLn2(int256 x) public pure {
        x = bound(x, 0, ExpLib.WEXP_UPPER_BOUND - ExpLib.LN_2_INT - 1);

        assertEq(ExpLib.wExp(x + ExpLib.LN_2_INT), 2 * ExpLib.wExp(x));
    }

    function testFuzz_wExp_IsNonDecreasing(int256 x, int256 y) public pure {
        x = bound(x, ExpLib.LN_WEI_INT, ExpLib.WEXP_UPPER_BOUND - 1);
        y = bound(y, x, ExpLib.WEXP_UPPER_BOUND - 1);

        assertLe(ExpLib.wExp(x), ExpLib.wExp(y));
    }
}
