// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {IBalanceOf} from "src/interfaces/IBalanceOf.sol";
import {TokenBalanceCondition} from "src/pool/irm/libraries/condition/TokenBalanceCondition.sol";
import {MockBalanceOf} from "../mocks/MockBalanceOf.sol";

contract TokenBalanceConditionUnitTest is Test {
    uint256 internal constant MINIMUM_BALANCE = 100;

    address internal account;

    MockBalanceOf internal token;

    function setUp() public {
        account = makeAddr("account");
        token = new MockBalanceOf();
    }

    // isValid()

    function test_isValid_ReturnsTrueForValidParams() public view {
        assertTrue(TokenBalanceCondition.isValid(_params(address(token), MINIMUM_BALANCE)));
    }

    function test_isValid_ReturnsTrueForMinimumPositiveBalance() public view {
        assertTrue(TokenBalanceCondition.isValid(_params(address(token), 1)));
    }

    function test_isValid_ReturnsFalseWhenParamsAreEmpty() public view {
        assertFalse(TokenBalanceCondition.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsBelow64() public view {
        assertFalse(TokenBalanceCondition.isValid(new bytes(63)));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsAbove64() public view {
        assertFalse(TokenBalanceCondition.isValid(new bytes(65)));
    }

    function test_isValid_ReturnsFalseWhenMinimumBalanceIsZero() public view {
        assertFalse(TokenBalanceCondition.isValid(_params(address(token), 0)));
    }

    function test_isValid_ReturnsFalseWhenTokenHasNoCode() public {
        address nonContractToken = makeAddr("nonContractToken");

        bool valid = TokenBalanceCondition.isValid(_params(nonContractToken, 1));

        assertFalse(valid);
    }

    function test_isValid_ReturnsFalseWhenBalanceOfReverts() public {
        token.setShouldRevert(true);

        bool valid = TokenBalanceCondition.isValid(_params(address(token), 1));

        assertFalse(valid);
    }

    function test_isValid_ReturnsFalseWhenBalanceOfReturns31Bytes() public {
        token.setReturnDataLength(31);

        bool valid = TokenBalanceCondition.isValid(_params(address(token), 1));

        assertFalse(valid);
    }

    function test_isValid_ReturnsFalseWhenBalanceOfReturns33Bytes() public {
        token.setReturnDataLength(33);

        bool valid = TokenBalanceCondition.isValid(_params(address(token), 1));

        assertFalse(valid);
    }

    function test_isValid_RevertsWhenParamsCannotBeDecoded() public {
        bytes memory malformedParams = abi.encode(type(uint256).max, uint256(1));

        vm.expectRevert();
        this.isValid(malformedParams);
    }

    // isApplicable()

    function test_isApplicable_ReturnsTrueWhenBalanceIsAboveMinimum() public {
        token.setBalance(account, MINIMUM_BALANCE + 1);

        bool applicable = TokenBalanceCondition.isApplicable(_params(address(token), MINIMUM_BALANCE), account);

        assertTrue(applicable);
    }

    function test_isApplicable_ReturnsTrueWhenBalanceEqualsMinimum() public {
        token.setBalance(account, MINIMUM_BALANCE);

        bool applicable = TokenBalanceCondition.isApplicable(_params(address(token), MINIMUM_BALANCE), account);

        assertTrue(applicable);
    }

    function test_isApplicable_ReturnsFalseWhenBalanceIsBelowMinimum() public {
        token.setBalance(account, MINIMUM_BALANCE - 1);

        bool applicable = TokenBalanceCondition.isApplicable(_params(address(token), MINIMUM_BALANCE), account);

        assertFalse(applicable);
    }

    function test_isApplicable_QueriesConfiguredTokenForAccount() public {
        bytes memory params = _params(address(token), MINIMUM_BALANCE);

        vm.expectCall(address(token), abi.encodeCall(IBalanceOf.balanceOf, (account)));

        TokenBalanceCondition.isApplicable(params, account);
    }

    function test_isApplicable_RevertsWhenParamsCannotBeDecoded() public {
        vm.expectRevert();
        this.isApplicable("", account);
    }

    function test_isApplicable_PropagatesBalanceOfRevert() public {
        token.setShouldRevert(true);

        vm.expectRevert(MockBalanceOf.BalanceOfReverted.selector);
        this.isApplicable(_params(address(token), MINIMUM_BALANCE), account);
    }

    function isValid(bytes calldata params) external view returns (bool) {
        return TokenBalanceCondition.isValid(params);
    }

    function isApplicable(bytes calldata params, address account_) external view returns (bool) {
        return TokenBalanceCondition.isApplicable(params, account_);
    }

    function _params(address token_, uint256 minimumBalance) private pure returns (bytes memory) {
        return abi.encode(token_, minimumBalance);
    }
}
