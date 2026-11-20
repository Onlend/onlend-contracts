// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {AlwaysApplicableCondition} from "src/pool/irm/libraries/condition/AlwaysApplicableCondition.sol";

contract AlwaysApplicableConditionFuzzTest is Test {
    // isValid()

    function testFuzz_isValid_ReturnsFalseWhenParamsAreNotEmpty(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 1, 1024);

        assertFalse(AlwaysApplicableCondition.isValid(new bytes(paramsLength)));
    }

    // isApplicable()

    function testFuzz_isApplicable_ReturnsTrueForAnyParamsAndAccount(bytes memory params, address account) public pure {
        assertTrue(AlwaysApplicableCondition.isApplicable(params, account));
    }
}
