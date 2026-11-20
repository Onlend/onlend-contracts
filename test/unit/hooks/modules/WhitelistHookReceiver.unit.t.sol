// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {WhitelistHookReceiver} from "src/hooks/modules/WhitelistHookReceiver.sol";
import {IHookReceiver, Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {Whitelistable} from "src/whitelist/abstract/Whitelistable.sol";

contract WhitelistHookReceiverUnitTest is Test {
    address internal defaultAdmin;
    address internal whitelistConfigurator;
    address internal account;
    address internal counterparty;
    WhitelistHookReceiver internal implementation;
    WhitelistHookReceiver internal whitelistHookReceiver;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        whitelistConfigurator = makeAddr("whitelistConfigurator");
        account = makeAddr("account");
        counterparty = makeAddr("counterparty");
        implementation = new WhitelistHookReceiver();

        whitelistHookReceiver = _clone();
        whitelistHookReceiver.initialize(defaultAdmin, whitelistConfigurator, new Whitelistable.WhitelistUpdate[](0));
    }

    // initialize()

    function test_initialize_InitializesWhitelist() public {
        Whitelistable.WhitelistUpdate[] memory updates = new Whitelistable.WhitelistUpdate[](1);
        updates[0] = Whitelistable.WhitelistUpdate({account: account, isWhitelisted: true});
        WhitelistHookReceiver instance = _clone();

        instance.initialize(defaultAdmin, whitelistConfigurator, updates);

        assertTrue(instance.hasRole(instance.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(instance.hasRole(instance.WHITELIST_CONFIG_ROLE(), whitelistConfigurator));
        assertTrue(instance.isWhitelisted(account));
    }

    function test_initialize_AllowsZeroDefaultAdmin() public {
        WhitelistHookReceiver instance = _clone();

        instance.initialize(address(0), whitelistConfigurator, new Whitelistable.WhitelistUpdate[](0));

        assertEq(instance.getRoleMemberCount(instance.DEFAULT_ADMIN_ROLE()), 0);
    }

    // onHook()

    function test_onHook_AllowsAccountActionWhenOnlyAccountIsWhitelisted() public {
        _setWhitelisted(account, true);

        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.BEFORE, ActionLib.POOL_DEPOSIT, abi.encode(account, counterparty)
        );
    }

    function test_onHook_AllowsAccountActionWhenDataIsExactlyOneWord() public {
        _setWhitelisted(account, true);

        whitelistHookReceiver.onHook(makeAddr("hookSource"), Phase.BEFORE, ActionLib.POOL_DEPOSIT, abi.encode(account));
    }

    function test_onHook_AllowsCounterpartyActionWhenOnlyCounterpartyIsWhitelisted() public {
        _setWhitelisted(counterparty, true);

        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.BEFORE, ActionLib.POOL_TRANSFER, abi.encode(account, counterparty)
        );
    }

    function test_onHook_RevertsWhenPhaseIsAfter() public {
        _setWhitelisted(account, true);

        vm.expectRevert(abi.encodeWithSelector(WhitelistHookReceiver.UnsupportedPhase.selector, Phase.AFTER));
        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.AFTER, ActionLib.POOL_DEPOSIT, abi.encode(account, counterparty)
        );
    }

    function test_onHook_RevertsWhenAccountIsNotWhitelisted() public {
        _setWhitelisted(counterparty, true);

        vm.expectRevert(abi.encodeWithSelector(Whitelistable.AccountNotWhitelisted.selector, account));
        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.BEFORE, ActionLib.POOL_DEPOSIT, abi.encode(account, counterparty)
        );
    }

    function test_onHook_RevertsWhenCounterpartyIsNotWhitelisted() public {
        _setWhitelisted(account, true);

        vm.expectRevert(abi.encodeWithSelector(Whitelistable.AccountNotWhitelisted.selector, counterparty));
        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.BEFORE, ActionLib.POOL_TRANSFER, abi.encode(account, counterparty)
        );
    }

    function test_onHook_RevertsWhenActionIsUnsupported() public {
        _setWhitelisted(account, true);
        _setWhitelisted(counterparty, true);

        vm.expectRevert(abi.encodeWithSelector(WhitelistHookReceiver.UnsupportedAction.selector, ActionLib.POOL_REPAY));
        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.BEFORE, ActionLib.POOL_REPAY, abi.encode(account, counterparty)
        );
    }

    function test_onHook_RevertsWhenDataIsShorterThanAccount() public {
        vm.expectRevert(WhitelistHookReceiver.InvalidHookData.selector);
        whitelistHookReceiver.onHook(makeAddr("hookSource"), Phase.BEFORE, ActionLib.POOL_DEPOSIT, new bytes(31));
    }

    function test_onHook_RevertsWhenDataIsShorterThanCounterparty() public {
        vm.expectRevert(WhitelistHookReceiver.InvalidHookData.selector);
        whitelistHookReceiver.onHook(makeAddr("hookSource"), Phase.BEFORE, ActionLib.POOL_TRANSFER, new bytes(63));
    }

    function test_onHook_RevertsWhenCheckedWordIsNotAnAddress() public {
        vm.expectRevert();
        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.BEFORE, ActionLib.POOL_DEPOSIT, abi.encode(type(uint256).max)
        );
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(whitelistHookReceiver.contractName(), "WhitelistHookReceiver");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(whitelistHookReceiver.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_HookReceiver_ReturnsTrue() public view {
        assertTrue(whitelistHookReceiver.supportsInterface(type(IHookReceiver).interfaceId));
    }

    function test_supportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(whitelistHookReceiver.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(whitelistHookReceiver.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_AccessControl_ReturnsTrue() public view {
        assertTrue(whitelistHookReceiver.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_AccessControlEnumerable_ReturnsTrue() public view {
        assertTrue(whitelistHookReceiver.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(whitelistHookReceiver.supportsInterface(0xffffffff));
        assertFalse(whitelistHookReceiver.supportsInterface(0xdeadbeef));
    }

    function _setWhitelisted(address account_, bool isWhitelisted) internal {
        vm.prank(whitelistConfigurator);
        whitelistHookReceiver.setWhitelisted(_singleUpdate(account_, isWhitelisted));
    }

    function _clone() internal returns (WhitelistHookReceiver) {
        return WhitelistHookReceiver(Clones.clone(address(implementation)));
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
