// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {TokenBalanceCondition} from "src/pool/irm/libraries/condition/TokenBalanceCondition.sol";
import {MockBalanceOf} from "../mocks/MockBalanceOf.sol";

contract TokenBalanceConditionFuzzTest is Test {
    uint256 internal constant MINIMUM_BALANCE = 100;

    MockBalanceOf internal token;

    function setUp() public {
        token = new MockBalanceOf();
    }

    // isValid()

    function testFuzz_isValid_ReturnsTrueForPositiveMinimumBalance(uint256 minimumBalance) public view {
        minimumBalance = bound(minimumBalance, 1, type(uint256).max);

        assertTrue(TokenBalanceCondition.isValid(_params(address(token), minimumBalance)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsBelow64(uint256 paramsLength) public view {
        paramsLength = bound(paramsLength, 0, 63);

        assertFalse(TokenBalanceCondition.isValid(new bytes(paramsLength)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsAbove64(uint256 paramsLength) public view {
        paramsLength = bound(paramsLength, 65, 1024);

        assertFalse(TokenBalanceCondition.isValid(new bytes(paramsLength)));
    }

    function testFuzz_isValid_ReturnsFalseWhenBalanceOfReturnsLessThan32Bytes(uint256 returnDataLength) public {
        returnDataLength = bound(returnDataLength, 0, 31);
        token.setReturnDataLength(returnDataLength);

        assertFalse(TokenBalanceCondition.isValid(_params(address(token), MINIMUM_BALANCE)));
    }

    function testFuzz_isValid_ReturnsFalseWhenBalanceOfReturnsMoreThan32Bytes(uint256 returnDataLength) public {
        returnDataLength = bound(returnDataLength, 33, 1024);
        token.setReturnDataLength(returnDataLength);

        assertFalse(TokenBalanceCondition.isValid(_params(address(token), MINIMUM_BALANCE)));
    }

    // isApplicable()

    function testFuzz_isApplicable_ReturnsTrueWhenBalanceIsAtLeastMinimum(
        address account,
        uint256 balance,
        uint256 minimumBalance
    ) public {
        minimumBalance = bound(minimumBalance, 1, type(uint256).max);
        balance = bound(balance, minimumBalance, type(uint256).max);
        token.setBalance(account, balance);

        assertTrue(TokenBalanceCondition.isApplicable(_params(address(token), minimumBalance), account));
    }

    function testFuzz_isApplicable_ReturnsFalseWhenBalanceIsBelowMinimum(
        address account,
        uint256 balance,
        uint256 minimumBalance
    ) public {
        minimumBalance = bound(minimumBalance, 1, type(uint256).max);
        balance = bound(balance, 0, minimumBalance - 1);
        token.setBalance(account, balance);

        assertFalse(TokenBalanceCondition.isApplicable(_params(address(token), minimumBalance), account));
    }

    function _params(address token_, uint256 minimumBalance) private pure returns (bytes memory) {
        return abi.encode(token_, minimumBalance);
    }
}
