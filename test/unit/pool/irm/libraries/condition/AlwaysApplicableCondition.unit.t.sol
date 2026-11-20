// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {AlwaysApplicableCondition} from "src/pool/irm/libraries/condition/AlwaysApplicableCondition.sol";

contract AlwaysApplicableConditionUnitTest is Test {
    // isValid()

    function test_isValid_ReturnsTrueForEmptyParams() public pure {
        assertTrue(AlwaysApplicableCondition.isValid(""));
    }

    function test_isValid_ReturnsFalseForNonEmptyParams() public pure {
        assertFalse(AlwaysApplicableCondition.isValid(abi.encode(uint256(1))));
    }

    // isApplicable()

    function test_isApplicable_ReturnsTrueForAnyAddress() public view {
        assertTrue(AlwaysApplicableCondition.isApplicable("", address(this)));
        assertTrue(AlwaysApplicableCondition.isApplicable("", address(0)));
    }
}
