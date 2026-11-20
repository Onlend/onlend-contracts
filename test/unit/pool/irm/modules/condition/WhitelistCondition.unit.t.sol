// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {Whitelistable} from "src/whitelist/abstract/Whitelistable.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IConditionModule} from "src/pool/irm/interfaces/IConditionModule.sol";
import {IValidatableModule} from "src/pool/irm/interfaces/IValidatableModule.sol";
import {WhitelistCondition} from "src/pool/irm/modules/condition/WhitelistCondition.sol";

contract WhitelistConditionUnitTest is Test {
    address internal defaultAdmin;
    address internal whitelistConfigurator;
    address internal account;
    WhitelistCondition internal implementation;
    WhitelistCondition internal whitelistCondition;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        whitelistConfigurator = makeAddr("whitelistConfigurator");
        account = makeAddr("account");
        implementation = new WhitelistCondition();

        whitelistCondition = _clone();
        whitelistCondition.initialize(defaultAdmin, whitelistConfigurator, new Whitelistable.WhitelistUpdate[](0));
    }

    // initialize()

    function test_initialize_InitializesWhitelist() public {
        Whitelistable.WhitelistUpdate[] memory updates = new Whitelistable.WhitelistUpdate[](1);
        updates[0] = Whitelistable.WhitelistUpdate({account: account, isWhitelisted: true});
        WhitelistCondition instance = _clone();

        instance.initialize(defaultAdmin, whitelistConfigurator, updates);

        assertTrue(instance.hasRole(instance.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(instance.hasRole(instance.WHITELIST_CONFIG_ROLE(), whitelistConfigurator));
        assertTrue(instance.isWhitelisted(account));
    }

    function test_initialize_AllowsZeroDefaultAdmin() public {
        WhitelistCondition instance = _clone();

        instance.initialize(address(0), whitelistConfigurator, new Whitelistable.WhitelistUpdate[](0));

        assertEq(instance.getRoleMemberCount(instance.DEFAULT_ADMIN_ROLE()), 0);
    }

    // isApplicable()

    function test_isApplicable_ReturnsTrueForWhitelistedAccount() public {
        _setWhitelisted(account, true);

        assertTrue(whitelistCondition.isApplicable("", account));
    }

    function test_isApplicable_ReturnsFalseForNonWhitelistedAccount() public view {
        assertFalse(whitelistCondition.isApplicable("", account));
    }

    function test_isApplicable_IgnoresParams() public {
        _setWhitelisted(account, true);

        bool applicableWithEmptyParams = whitelistCondition.isApplicable("", account);
        bool applicableWithNonEmptyParams = whitelistCondition.isApplicable(hex"deadbeef", account);

        assertEq(applicableWithNonEmptyParams, applicableWithEmptyParams);
    }

    // isValid()

    function test_isValid_ReturnsTrueWhenParamsAreEmpty() public view {
        assertTrue(whitelistCondition.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsAreNotEmpty() public view {
        assertFalse(whitelistCondition.isValid(new bytes(1)));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(whitelistCondition.contractName(), "WhitelistCondition");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(whitelistCondition.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_ConditionModule_ReturnsTrue() public view {
        assertTrue(whitelistCondition.supportsInterface(type(IConditionModule).interfaceId));
    }

    function test_supportsInterface_ValidatableModule_ReturnsTrue() public view {
        assertTrue(whitelistCondition.supportsInterface(type(IValidatableModule).interfaceId));
    }

    function test_supportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(whitelistCondition.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_AccessControl_ReturnsTrue() public view {
        assertTrue(whitelistCondition.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_AccessControlEnumerable_ReturnsTrue() public view {
        assertTrue(whitelistCondition.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(whitelistCondition.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(whitelistCondition.supportsInterface(0xffffffff));
        assertFalse(whitelistCondition.supportsInterface(0xdeadbeef));
    }

    function _setWhitelisted(address account_, bool isWhitelisted) internal {
        vm.prank(whitelistConfigurator);
        whitelistCondition.setWhitelisted(_singleUpdate(account_, isWhitelisted));
    }

    function _clone() internal returns (WhitelistCondition) {
        return WhitelistCondition(Clones.clone(address(implementation)));
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
