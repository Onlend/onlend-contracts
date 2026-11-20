// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {MultiHookReceiver} from "src/hooks/MultiHookReceiver.sol";
import {IHookReceiver, Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {MockHookReceiver} from "./mocks/MockHookReceiver.sol";

contract MultiHookReceiverUnitTest is Test {
    address internal defaultAdmin;
    address internal hookReceiversUpdater;
    address internal nonHookReceiversUpdater;
    address internal hookCaller;
    address internal secondHookCaller;
    address internal nonHookCaller;
    MultiHookReceiver internal implementation;
    MultiHookReceiver internal multiHookReceiver;
    MockHookReceiver internal firstHookReceiver;
    MockHookReceiver internal secondHookReceiver;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        hookReceiversUpdater = makeAddr("hookReceiversUpdater");
        nonHookReceiversUpdater = makeAddr("nonHookReceiversUpdater");
        hookCaller = makeAddr("hookCaller");
        secondHookCaller = makeAddr("secondHookCaller");
        nonHookCaller = makeAddr("nonHookCaller");
        implementation = new MultiHookReceiver();

        multiHookReceiver = _clone();
        multiHookReceiver.initialize(
            defaultAdmin, hookReceiversUpdater, _hookCallers(), new MultiHookReceiver.HookReceiverConfig[](0)
        );
        firstHookReceiver = new MockHookReceiver();
        secondHookReceiver = new MockHookReceiver();
    }

    // initialize()

    function test_initialize_GrantsDefaultAdminHookReceiversUpdaterAndHookCallerRoles() public view {
        assertTrue(multiHookReceiver.hasRole(multiHookReceiver.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(multiHookReceiver.hasRole(multiHookReceiver.HOOK_RECEIVERS_UPDATER_ROLE(), hookReceiversUpdater));
        assertTrue(multiHookReceiver.hasRole(multiHookReceiver.HOOK_CALLER_ROLE(), hookCaller));
        assertTrue(multiHookReceiver.hasRole(multiHookReceiver.HOOK_CALLER_ROLE(), secondHookCaller));
    }

    function test_initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(
            multiHookReceiver.getRoleAdmin(multiHookReceiver.HOOK_RECEIVERS_UPDATER_ROLE()),
            multiHookReceiver.DEFAULT_ADMIN_ROLE()
        );
        assertEq(
            multiHookReceiver.getRoleAdmin(multiHookReceiver.HOOK_CALLER_ROLE()), multiHookReceiver.DEFAULT_ADMIN_ROLE()
        );
    }

    function test_initialize_AllowsNoInitialRoleMembers() public {
        MultiHookReceiver rolelessMultiHookReceiver = _clone();
        rolelessMultiHookReceiver.initialize(
            address(0), address(0), new address[](0), new MultiHookReceiver.HookReceiverConfig[](0)
        );

        assertEq(rolelessMultiHookReceiver.getRoleMemberCount(rolelessMultiHookReceiver.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(
            rolelessMultiHookReceiver.getRoleMemberCount(rolelessMultiHookReceiver.HOOK_RECEIVERS_UPDATER_ROLE()), 0
        );
        assertEq(rolelessMultiHookReceiver.getRoleMemberCount(rolelessMultiHookReceiver.HOOK_CALLER_ROLE()), 0);
    }

    function test_initialize_SetsInitialHookReceiverConfigs() public {
        address[] memory beforeHookReceivers = _hookReceivers(address(firstHookReceiver), address(secondHookReceiver));
        address[] memory afterHookReceivers = _hookReceivers(address(secondHookReceiver));
        MultiHookReceiver.HookReceiverConfig[] memory configs = new MultiHookReceiver.HookReceiverConfig[](2);
        configs[0] =
            MultiHookReceiver.HookReceiverConfig({phase: Phase.BEFORE, action: 5, hookReceivers: beforeHookReceivers});
        configs[1] =
            MultiHookReceiver.HookReceiverConfig({phase: Phase.AFTER, action: 7, hookReceivers: afterHookReceivers});
        MultiHookReceiver instance = _clone();

        vm.expectEmit();
        emit MultiHookReceiver.HookReceiversSet(Phase.BEFORE, 5, beforeHookReceivers);
        vm.expectEmit();
        emit MultiHookReceiver.HookReceiversSet(Phase.AFTER, 7, afterHookReceivers);

        instance.initialize(defaultAdmin, hookReceiversUpdater, _hookCallers(), configs);

        assertEq(instance.getHookReceivers(Phase.BEFORE, 5), beforeHookReceivers);
        assertEq(instance.getHookReceivers(Phase.AFTER, 7), afterHookReceivers);
    }

    // setHookReceivers()

    function test_setHookReceivers_SetsHookReceivers() public {
        address[] memory hookReceivers = _hookReceivers(address(firstHookReceiver), address(secondHookReceiver));
        MultiHookReceiver.HookReceiverConfig[] memory configs = _hookReceiverConfigs(Phase.BEFORE, 5, hookReceivers);

        vm.expectEmit(true, true, false, true);
        emit MultiHookReceiver.HookReceiversSet(Phase.BEFORE, 5, hookReceivers);

        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(configs);

        assertEq(multiHookReceiver.getHookReceivers(Phase.BEFORE, 5), hookReceivers);
    }

    function test_setHookReceivers_SetsMultipleHookReceiverConfigs() public {
        address[] memory beforeHookReceivers = _hookReceivers(address(firstHookReceiver), address(secondHookReceiver));
        address[] memory afterHookReceivers = _hookReceivers(address(secondHookReceiver));
        MultiHookReceiver.HookReceiverConfig[] memory configs = new MultiHookReceiver.HookReceiverConfig[](2);
        configs[0] =
            MultiHookReceiver.HookReceiverConfig({phase: Phase.BEFORE, action: 5, hookReceivers: beforeHookReceivers});
        configs[1] =
            MultiHookReceiver.HookReceiverConfig({phase: Phase.AFTER, action: 7, hookReceivers: afterHookReceivers});

        vm.expectEmit(true, true, false, true);
        emit MultiHookReceiver.HookReceiversSet(Phase.BEFORE, 5, beforeHookReceivers);
        vm.expectEmit(true, true, false, true);
        emit MultiHookReceiver.HookReceiversSet(Phase.AFTER, 7, afterHookReceivers);

        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(configs);

        assertEq(multiHookReceiver.getHookReceivers(Phase.BEFORE, 5), beforeHookReceivers);
        assertEq(multiHookReceiver.getHookReceivers(Phase.AFTER, 7), afterHookReceivers);
    }

    function test_setHookReceivers_DoesNothingWhenConfigsIsEmpty() public {
        address[] memory hookReceivers = _hookReceivers(address(firstHookReceiver), address(secondHookReceiver));
        MultiHookReceiver.HookReceiverConfig[] memory emptyConfigs = new MultiHookReceiver.HookReceiverConfig[](0);

        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(_hookReceiverConfigs(Phase.BEFORE, 5, hookReceivers));

        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(emptyConfigs);

        assertEq(multiHookReceiver.getHookReceivers(Phase.BEFORE, 5), hookReceivers);
    }

    function test_setHookReceivers_UsesLastConfigWhenPhaseAndActionRepeat() public {
        address[] memory firstHookReceivers = _hookReceivers(address(firstHookReceiver));
        address[] memory secondHookReceivers = _hookReceivers(address(secondHookReceiver));
        MultiHookReceiver.HookReceiverConfig[] memory configs = new MultiHookReceiver.HookReceiverConfig[](2);
        configs[0] =
            MultiHookReceiver.HookReceiverConfig({phase: Phase.BEFORE, action: 5, hookReceivers: firstHookReceivers});
        configs[1] =
            MultiHookReceiver.HookReceiverConfig({phase: Phase.BEFORE, action: 5, hookReceivers: secondHookReceivers});

        vm.expectEmit(true, true, false, true);
        emit MultiHookReceiver.HookReceiversSet(Phase.BEFORE, 5, firstHookReceivers);
        vm.expectEmit(true, true, false, true);
        emit MultiHookReceiver.HookReceiversSet(Phase.BEFORE, 5, secondHookReceivers);

        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(configs);

        assertEq(multiHookReceiver.getHookReceivers(Phase.BEFORE, 5), secondHookReceivers);
    }

    function test_setHookReceivers_ReplacesHookReceivers() public {
        address[] memory hookReceivers = _hookReceivers(address(firstHookReceiver));
        address[] memory newHookReceivers = _hookReceivers(address(secondHookReceiver));

        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(_hookReceiverConfigs(Phase.BEFORE, 5, hookReceivers));

        vm.expectEmit(true, true, false, true);
        emit MultiHookReceiver.HookReceiversSet(Phase.BEFORE, 5, newHookReceivers);

        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(_hookReceiverConfigs(Phase.BEFORE, 5, newHookReceivers));

        assertEq(multiHookReceiver.getHookReceivers(Phase.BEFORE, 5), newHookReceivers);
    }

    function test_setHookReceivers_ClearsHookReceivers() public {
        address[] memory hookReceivers = _hookReceivers(address(firstHookReceiver));
        address[] memory emptyHookReceivers = new address[](0);

        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(_hookReceiverConfigs(Phase.BEFORE, 5, hookReceivers));

        vm.expectEmit(true, true, false, true);
        emit MultiHookReceiver.HookReceiversSet(Phase.BEFORE, 5, emptyHookReceivers);

        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(_hookReceiverConfigs(Phase.BEFORE, 5, emptyHookReceivers));

        assertEq(multiHookReceiver.getHookReceivers(Phase.BEFORE, 5), emptyHookReceivers);
    }

    function test_setHookReceivers_RevertsWhenHookReceiverIsInvalid() public {
        address invalidHookReceiver = makeAddr("invalidHookReceiver");
        address[] memory hookReceivers = _hookReceivers(invalidHookReceiver);

        vm.expectRevert(abi.encodeWithSelector(MultiHookReceiver.InvalidHookReceiver.selector, invalidHookReceiver));
        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(_hookReceiverConfigs(Phase.BEFORE, 5, hookReceivers));
    }

    function test_setHookReceivers_RevertsAtomicallyWhenAnyConfigContainsInvalidHookReceiver() public {
        address invalidHookReceiver = makeAddr("invalidHookReceiver");
        address[] memory beforeHookReceivers = _hookReceivers(address(firstHookReceiver));
        address[] memory afterHookReceivers = _hookReceivers(address(secondHookReceiver));
        address[] memory invalidHookReceivers = _hookReceivers(invalidHookReceiver);
        MultiHookReceiver.HookReceiverConfig[] memory configs = new MultiHookReceiver.HookReceiverConfig[](3);
        configs[0] =
            MultiHookReceiver.HookReceiverConfig({phase: Phase.BEFORE, action: 5, hookReceivers: beforeHookReceivers});
        configs[1] =
            MultiHookReceiver.HookReceiverConfig({phase: Phase.AFTER, action: 7, hookReceivers: afterHookReceivers});
        configs[2] =
            MultiHookReceiver.HookReceiverConfig({phase: Phase.BEFORE, action: 9, hookReceivers: invalidHookReceivers});

        vm.expectRevert(abi.encodeWithSelector(MultiHookReceiver.InvalidHookReceiver.selector, invalidHookReceiver));
        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(configs);

        assertEq(multiHookReceiver.getHookReceivers(Phase.BEFORE, 5), new address[](0));
        assertEq(multiHookReceiver.getHookReceivers(Phase.AFTER, 7), new address[](0));
    }

    function test_setHookReceivers_RevertsWhenCallerIsNotHookReceiversUpdater() public {
        address[] memory hookReceivers = _hookReceivers(address(firstHookReceiver));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonHookReceiversUpdater,
                multiHookReceiver.HOOK_RECEIVERS_UPDATER_ROLE()
            )
        );
        vm.prank(nonHookReceiversUpdater);
        multiHookReceiver.setHookReceivers(_hookReceiverConfigs(Phase.BEFORE, 5, hookReceivers));
    }

    // onHook()

    function test_onHook_CallsAllHookReceiversForPhaseAndAction() public {
        address hookSource = makeAddr("hookSource");
        uint8 action = 5;
        bytes memory data = abi.encode("hook data");
        address[] memory hookReceivers = _hookReceivers(address(firstHookReceiver), address(secondHookReceiver));
        _setHookReceivers(Phase.BEFORE, action, hookReceivers);

        vm.prank(hookCaller);
        multiHookReceiver.onHook(hookSource, Phase.BEFORE, action, data);

        assertEq(firstHookReceiver.calls(), 1);
        assertEq(firstHookReceiver.lastHookSource(), hookSource);
        assertEq(uint256(firstHookReceiver.lastPhase()), uint256(Phase.BEFORE));
        assertEq(firstHookReceiver.lastAction(), action);
        assertEq(firstHookReceiver.lastData(), data);

        assertEq(secondHookReceiver.calls(), 1);
        assertEq(secondHookReceiver.lastHookSource(), hookSource);
        assertEq(uint256(secondHookReceiver.lastPhase()), uint256(Phase.BEFORE));
        assertEq(secondHookReceiver.lastAction(), action);
        assertEq(secondHookReceiver.lastData(), data);
    }

    function test_onHook_DoesNotCallHookReceiversConfiguredForDifferentPhase() public {
        uint8 action = 5;
        _setHookReceivers(Phase.BEFORE, action, _hookReceivers(address(firstHookReceiver)));

        vm.prank(hookCaller);
        multiHookReceiver.onHook(hookCaller, Phase.AFTER, action, abi.encode("hook data"));

        assertEq(firstHookReceiver.calls(), 0);
    }

    function test_onHook_DoesNotCallHookReceiversConfiguredForDifferentAction() public {
        _setHookReceivers(Phase.BEFORE, 5, _hookReceivers(address(firstHookReceiver)));

        vm.prank(hookCaller);
        multiHookReceiver.onHook(hookCaller, Phase.BEFORE, 7, abi.encode("hook data"));

        assertEq(firstHookReceiver.calls(), 0);
    }

    function test_onHook_RevertsWhenCallerIsNotHookCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonHookCaller,
                multiHookReceiver.HOOK_CALLER_ROLE()
            )
        );
        vm.prank(nonHookCaller);
        multiHookReceiver.onHook(nonHookCaller, Phase.BEFORE, 5, abi.encode("hook data"));
    }

    function test_onHook_PropagatesHookReceiverRevert() public {
        uint8 action = 5;
        address[] memory hookReceivers = _hookReceivers(address(firstHookReceiver), address(secondHookReceiver));
        _setHookReceivers(Phase.BEFORE, action, hookReceivers);
        firstHookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(hookCaller);
        multiHookReceiver.onHook(hookCaller, Phase.BEFORE, action, abi.encode("hook data"));
    }

    // getHookReceivers()

    function test_getHookReceivers_ReturnsEmptyArrayWhenNotConfigured() public view {
        assertEq(multiHookReceiver.getHookReceivers(Phase.BEFORE, 5), new address[](0));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(multiHookReceiver.contractName(), "MultiHookReceiver");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(multiHookReceiver.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_HookReceiver_ReturnsTrue() public view {
        assertTrue(multiHookReceiver.supportsInterface(type(IHookReceiver).interfaceId));
    }

    function test_supportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(multiHookReceiver.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(multiHookReceiver.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_AccessControl_ReturnsTrue() public view {
        assertTrue(multiHookReceiver.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_AccessControlEnumerable_ReturnsTrue() public view {
        assertTrue(multiHookReceiver.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(multiHookReceiver.supportsInterface(0xffffffff));
        assertFalse(multiHookReceiver.supportsInterface(0xdeadbeef));
    }

    function _setHookReceivers(Phase phase, uint8 action, address[] memory hookReceivers) internal {
        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(_hookReceiverConfigs(phase, action, hookReceivers));
    }

    function _hookReceiverConfigs(Phase phase, uint8 action, address[] memory hookReceivers)
        internal
        pure
        returns (MultiHookReceiver.HookReceiverConfig[] memory configs)
    {
        configs = new MultiHookReceiver.HookReceiverConfig[](1);
        configs[0] = MultiHookReceiver.HookReceiverConfig({phase: phase, action: action, hookReceivers: hookReceivers});
    }

    function _hookReceivers(address hookReceiver) internal pure returns (address[] memory hookReceivers) {
        hookReceivers = new address[](1);
        hookReceivers[0] = hookReceiver;
    }

    function _hookReceivers(address first, address second) internal pure returns (address[] memory hookReceivers) {
        hookReceivers = new address[](2);
        hookReceivers[0] = first;
        hookReceivers[1] = second;
    }

    function _hookCallers() internal view returns (address[] memory hookCallers) {
        hookCallers = new address[](2);
        hookCallers[0] = hookCaller;
        hookCallers[1] = secondHookCaller;
    }

    function _clone() internal returns (MultiHookReceiver) {
        return MultiHookReceiver(Clones.clone(address(implementation)));
    }
}
