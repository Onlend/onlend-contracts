// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {Whitelistable} from "src/whitelist/abstract/Whitelistable.sol";
import {WhitelistableHarness} from "./mocks/WhitelistableHarness.sol";

contract WhitelistableUnitTest is Test {
    address internal defaultAdmin;
    address internal whitelistConfigurator;
    address internal nonWhitelistConfigurator;
    address internal account;
    WhitelistableHarness internal implementation;
    WhitelistableHarness internal whitelistable;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        whitelistConfigurator = makeAddr("whitelistConfigurator");
        nonWhitelistConfigurator = makeAddr("nonWhitelistConfigurator");
        account = makeAddr("account");
        implementation = new WhitelistableHarness();

        whitelistable = _clone();
        whitelistable.initialize(defaultAdmin, whitelistConfigurator, new Whitelistable.WhitelistUpdate[](0));
    }

    // initialize()

    function test_initialize_GrantsWhitelistConfiguratorRole() public view {
        assertTrue(whitelistable.hasRole(whitelistable.WHITELIST_CONFIG_ROLE(), whitelistConfigurator));
    }

    function test_initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(whitelistable.getRoleAdmin(whitelistable.WHITELIST_CONFIG_ROLE()), whitelistable.DEFAULT_ADMIN_ROLE());
    }

    function test_initialize_AllowsZeroWhitelistConfigurator() public {
        WhitelistableHarness instance = _clone();
        instance.initialize(defaultAdmin, address(0), new Whitelistable.WhitelistUpdate[](0));

        assertEq(instance.getRoleMemberCount(instance.WHITELIST_CONFIG_ROLE()), 0);
    }

    function test_initialize_AppliesInitialWhitelistUpdates() public {
        address firstAccount = makeAddr("firstAccount");
        address secondAccount = makeAddr("secondAccount");
        Whitelistable.WhitelistUpdate[] memory updates = new Whitelistable.WhitelistUpdate[](2);
        updates[0] = Whitelistable.WhitelistUpdate({account: firstAccount, isWhitelisted: true});
        updates[1] = Whitelistable.WhitelistUpdate({account: secondAccount, isWhitelisted: false});
        WhitelistableHarness instance = _clone();

        vm.expectEmit(address(instance));
        emit Whitelistable.WhitelistUpdated(firstAccount, true);
        vm.expectEmit(address(instance));
        emit Whitelistable.WhitelistUpdated(secondAccount, false);

        instance.initialize(defaultAdmin, whitelistConfigurator, updates);

        assertTrue(instance.isWhitelisted(firstAccount));
        assertFalse(instance.isWhitelisted(secondAccount));
    }

    // setWhitelisted()

    function test_setWhitelisted_SetsAccountWhitelisted() public {
        vm.expectEmit(address(whitelistable));
        emit Whitelistable.WhitelistUpdated(account, true);

        _setWhitelisted(account, true);

        assertTrue(whitelistable.isWhitelisted(account));
    }

    function test_setWhitelisted_SetsAccountNotWhitelisted() public {
        _setWhitelisted(account, true);

        vm.expectEmit(address(whitelistable));
        emit Whitelistable.WhitelistUpdated(account, false);

        _setWhitelisted(account, false);

        assertFalse(whitelistable.isWhitelisted(account));
    }

    function test_setWhitelisted_SetsMultipleAccounts() public {
        address firstAccount = makeAddr("firstAccount");
        address secondAccount = makeAddr("secondAccount");
        Whitelistable.WhitelistUpdate[] memory updates = new Whitelistable.WhitelistUpdate[](2);
        updates[0] = Whitelistable.WhitelistUpdate({account: firstAccount, isWhitelisted: true});
        updates[1] = Whitelistable.WhitelistUpdate({account: secondAccount, isWhitelisted: false});
        _setWhitelisted(secondAccount, true);

        vm.prank(whitelistConfigurator);
        whitelistable.setWhitelisted(updates);

        assertTrue(whitelistable.isWhitelisted(firstAccount));
        assertFalse(whitelistable.isWhitelisted(secondAccount));
    }

    function test_setWhitelisted_RevertsWhenCallerIsNotWhitelistConfigurator() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonWhitelistConfigurator,
                whitelistable.WHITELIST_CONFIG_ROLE()
            )
        );
        vm.prank(nonWhitelistConfigurator);
        whitelistable.setWhitelisted(_singleUpdate(account, true));
    }

    // _checkWhitelisted()

    function test_checkWhitelisted_PassesWhenAccountIsWhitelisted() public {
        _setWhitelisted(account, true);

        whitelistable.checkWhitelisted(account);
    }

    function test_checkWhitelisted_RevertsWhenAccountIsNotWhitelisted() public {
        vm.expectRevert(abi.encodeWithSelector(Whitelistable.AccountNotWhitelisted.selector, account));
        whitelistable.checkWhitelisted(account);
    }

    function _setWhitelisted(address account_, bool isWhitelisted) internal {
        vm.prank(whitelistConfigurator);
        whitelistable.setWhitelisted(_singleUpdate(account_, isWhitelisted));
    }

    function _clone() internal returns (WhitelistableHarness) {
        return WhitelistableHarness(Clones.clone(address(implementation)));
    }

    function _singleUpdate(address account_, bool isWhitelisted)
        internal
        pure
        returns (Whitelistable.WhitelistUpdate[] memory updates)
    {
        updates = new Whitelistable.WhitelistUpdate[](1);
        updates[0] = Whitelistable.WhitelistUpdate({account: account_, isWhitelisted: isWhitelisted});
    }
}
