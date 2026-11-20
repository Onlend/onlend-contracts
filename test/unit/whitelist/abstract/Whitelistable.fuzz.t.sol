// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {Whitelistable} from "src/whitelist/abstract/Whitelistable.sol";
import {WhitelistableHarness} from "./mocks/WhitelistableHarness.sol";

contract WhitelistableFuzzTest is Test {
    address internal defaultAdmin;
    address internal whitelistConfigurator;
    WhitelistableHarness internal implementation;
    WhitelistableHarness internal whitelistable;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        whitelistConfigurator = makeAddr("whitelistConfigurator");
        implementation = new WhitelistableHarness();

        whitelistable = _clone();
        whitelistable.initialize(defaultAdmin, whitelistConfigurator, new Whitelistable.WhitelistUpdate[](0));
    }

    // initialize()

    function testFuzz_initialize_AppliesInitialWhitelistUpdate(address account, bool isWhitelisted) public {
        Whitelistable.WhitelistUpdate[] memory updates = new Whitelistable.WhitelistUpdate[](1);
        updates[0] = Whitelistable.WhitelistUpdate({account: account, isWhitelisted: isWhitelisted});
        WhitelistableHarness instance = _clone();

        vm.expectEmit(address(instance));
        emit Whitelistable.WhitelistUpdated(account, isWhitelisted);

        instance.initialize(defaultAdmin, whitelistConfigurator, updates);

        assertEq(instance.isWhitelisted(account), isWhitelisted);
    }

    // setWhitelisted()

    function testFuzz_setWhitelisted_SetsWhitelistStatus(address account, bool isWhitelisted) public {
        _setWhitelisted(account, !isWhitelisted);

        _setWhitelisted(account, isWhitelisted);

        assertEq(whitelistable.isWhitelisted(account), isWhitelisted);
    }

    function _setWhitelisted(address account, bool isWhitelisted) internal {
        Whitelistable.WhitelistUpdate[] memory updates = new Whitelistable.WhitelistUpdate[](1);
        updates[0] = Whitelistable.WhitelistUpdate({account: account, isWhitelisted: isWhitelisted});

        vm.prank(whitelistConfigurator);
        whitelistable.setWhitelisted(updates);
    }

    function _clone() internal returns (WhitelistableHarness) {
        return WhitelistableHarness(Clones.clone(address(implementation)));
    }
}
