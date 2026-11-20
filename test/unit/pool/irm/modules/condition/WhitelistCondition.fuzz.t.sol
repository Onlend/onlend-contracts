// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {Whitelistable} from "src/whitelist/abstract/Whitelistable.sol";
import {WhitelistCondition} from "src/pool/irm/modules/condition/WhitelistCondition.sol";

contract WhitelistConditionFuzzTest is Test {
    address internal defaultAdmin;
    address internal whitelistConfigurator;

    WhitelistCondition internal implementation;
    WhitelistCondition internal whitelistCondition;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        whitelistConfigurator = makeAddr("whitelistConfigurator");
        implementation = new WhitelistCondition();

        whitelistCondition = _clone();
        whitelistCondition.initialize(defaultAdmin, whitelistConfigurator, new Whitelistable.WhitelistUpdate[](0));
    }

    // isApplicable()

    function testFuzz_isApplicable_ReturnsTrueForWhitelistedAccount(bytes memory params, address account) public {
        _setWhitelisted(account, true);

        assertTrue(whitelistCondition.isApplicable(params, account));
    }

    function testFuzz_isApplicable_ReturnsFalseForNonWhitelistedAccount(bytes memory params, address account) public {
        _setWhitelisted(account, true);
        _setWhitelisted(account, false);

        assertFalse(whitelistCondition.isApplicable(params, account));
    }

    // isValid()

    function testFuzz_isValid_ReturnsFalseWhenParamsAreNotEmpty(uint256 paramsLength) public view {
        paramsLength = bound(paramsLength, 1, 1024);

        assertFalse(whitelistCondition.isValid(new bytes(paramsLength)));
    }

    function _setWhitelisted(address account, bool whitelisted) internal {
        Whitelistable.WhitelistUpdate[] memory updates = new Whitelistable.WhitelistUpdate[](1);
        updates[0] = Whitelistable.WhitelistUpdate({account: account, isWhitelisted: whitelisted});

        vm.prank(whitelistConfigurator);
        whitelistCondition.setWhitelisted(updates);
    }

    function _clone() internal returns (WhitelistCondition) {
        return WhitelistCondition(Clones.clone(address(implementation)));
    }
}
