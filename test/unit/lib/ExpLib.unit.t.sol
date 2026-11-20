// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ExpLib} from "src/lib/ExpLib.sol";

contract ExpLibUnitTest is Test {
    // wExp()

    function test_wExp_ReturnsOneAtZero() public pure {
        assertEq(ExpLib.wExp(0), 1e18);
    }

    function test_wExp_ReturnsTwoAtLn2() public pure {
        assertEq(ExpLib.wExp(ExpLib.LN_2_INT), 2e18);
    }

    function test_wExp_ReturnsHalfAtMinusLn2() public pure {
        assertEq(ExpLib.wExp(-ExpLib.LN_2_INT), 0.5e18);
    }

    function test_wExp_ApproximatesEAtOne() public pure {
        // e^r is approximated to within 1% for |r| <= ln(2)/2
        assertApproxEqRel(ExpLib.wExp(1e18), 2.718281828459045235e18, 0.01e18);
    }

    function test_wExp_ReturnsZeroJustBelowLowerBound() public pure {
        assertEq(ExpLib.wExp(ExpLib.LN_WEI_INT - 1), 0);
    }

    function test_wExp_ReturnsAtMostUpperValueJustBelowUpperBound() public pure {
        assertLe(ExpLib.wExp(ExpLib.WEXP_UPPER_BOUND - 1), ExpLib.WEXP_UPPER_VALUE);
    }

    function test_wExp_ReturnsUpperValueAtUpperBound() public pure {
        assertEq(ExpLib.wExp(ExpLib.WEXP_UPPER_BOUND), ExpLib.WEXP_UPPER_VALUE);
    }
}
