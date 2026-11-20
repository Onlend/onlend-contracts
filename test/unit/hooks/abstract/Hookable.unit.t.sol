// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {Hookable} from "src/hooks/abstract/Hookable.sol";
import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {HookableHarness} from "../mocks/HookableHarness.sol";
import {MockHookReceiver} from "../mocks/MockHookReceiver.sol";

contract HookableUnitTest is Test {
    address internal defaultAdmin;
    address internal hookUpdater;
    address internal nonHookUpdater;
    HookableHarness internal implementation;
    HookableHarness internal hookable;
    MockHookReceiver internal hookReceiver;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        hookUpdater = makeAddr("hookUpdater");
        nonHookUpdater = makeAddr("nonHookUpdater");

        implementation = new HookableHarness();
        hookable = HookableHarness(Clones.clone(address(implementation)));
        hookable.initialize(defaultAdmin, hookUpdater, address(0), 0, 0);
        hookReceiver = new MockHookReceiver();
    }

    // initialize()

    function test_initialize_GrantsHookUpdaterRole() public view {
        assertTrue(hookable.hasRole(hookable.HOOK_UPDATER_ROLE(), hookUpdater));
    }

    function test_initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(hookable.getRoleAdmin(hookable.HOOK_UPDATER_ROLE()), hookable.DEFAULT_ADMIN_ROLE());
    }

    function test_initialize_AllowsZeroHookUpdater() public {
        HookableHarness rolelessHookable = HookableHarness(Clones.clone(address(implementation)));
        rolelessHookable.initialize(defaultAdmin, address(0), address(0), 0, 0);

        assertEq(rolelessHookable.getRoleMemberCount(rolelessHookable.HOOK_UPDATER_ROLE()), 0);
    }

    function test_initialize_AllowsDisabledHooks() public view {
        assertEq(hookable.hookReceiver(), address(0));
        (uint256 beforeBitmap, uint256 afterBitmap) = hookable.hookBitmaps();
        assertEq(beforeBitmap, 0);
        assertEq(afterBitmap, 0);
    }

    function test_initialize_SetsInitialHookConfiguration() public {
        uint256 beforeBitmap = _bit(5);
        uint256 afterBitmap = _bit(7);
        HookableHarness configuredHookable = HookableHarness(Clones.clone(address(implementation)));

        configuredHookable.initialize(defaultAdmin, hookUpdater, address(hookReceiver), beforeBitmap, afterBitmap);

        assertEq(configuredHookable.hookReceiver(), address(hookReceiver));
        (uint256 configuredBeforeBitmap, uint256 configuredAfterBitmap) = configuredHookable.hookBitmaps();
        assertEq(configuredBeforeBitmap, beforeBitmap);
        assertEq(configuredAfterBitmap, afterBitmap);
    }

    // setHookReceiver()

    function test_setHookReceiver_SetsHookReceiver() public {
        vm.expectEmit(true, true, false, false);
        emit Hookable.HookReceiverSet(address(0), address(hookReceiver));

        vm.prank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));

        assertEq(hookable.hookReceiver(), address(hookReceiver));
    }

    function test_setHookReceiver_ReplacesHookReceiver() public {
        MockHookReceiver newHookReceiver = new MockHookReceiver();

        vm.prank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));

        vm.expectEmit(true, true, false, false);
        emit Hookable.HookReceiverSet(address(hookReceiver), address(newHookReceiver));

        vm.prank(hookUpdater);
        hookable.setHookReceiver(address(newHookReceiver));

        assertEq(hookable.hookReceiver(), address(newHookReceiver));
    }

    function test_setHookReceiver_ClearsHookReceiver() public {
        vm.prank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));

        vm.expectEmit(true, true, false, false);
        emit Hookable.HookReceiverSet(address(hookReceiver), address(0));

        vm.prank(hookUpdater);
        hookable.setHookReceiver(address(0));

        assertEq(hookable.hookReceiver(), address(0));
    }

    function test_setHookReceiver_RevertsWhenHookReceiverIsInvalid() public {
        address invalidHookReceiver = makeAddr("invalidHookReceiver");

        vm.expectRevert(abi.encodeWithSelector(Hookable.InvalidHookReceiver.selector, invalidHookReceiver));
        vm.prank(hookUpdater);
        hookable.setHookReceiver(invalidHookReceiver);
    }

    function test_setHookReceiver_RevertsWhenCallerIsNotHookUpdater() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonHookUpdater, hookable.HOOK_UPDATER_ROLE()
            )
        );
        vm.prank(nonHookUpdater);
        hookable.setHookReceiver(address(hookReceiver));
    }

    // setHookBitmaps()

    function test_setHookBitmaps_SetsHookBitmaps() public {
        uint256 beforeBitmap = _bit(5);
        uint256 afterBitmap = _bit(7);

        vm.expectEmit();
        emit Hookable.HookBitmapsSet(0, 0, beforeBitmap, afterBitmap);

        vm.prank(hookUpdater);
        hookable.setHookBitmaps(beforeBitmap, afterBitmap);

        (uint256 configuredBeforeBitmap, uint256 configuredAfterBitmap) = hookable.hookBitmaps();
        assertEq(configuredBeforeBitmap, beforeBitmap);
        assertEq(configuredAfterBitmap, afterBitmap);
    }

    function test_setHookBitmaps_ReplacesHookBitmaps() public {
        uint256 beforeBitmap = _bit(5);
        uint256 afterBitmap = _bit(7);
        uint256 newBeforeBitmap = _bit(11);
        uint256 newAfterBitmap = _bit(13);

        vm.prank(hookUpdater);
        hookable.setHookBitmaps(beforeBitmap, afterBitmap);

        vm.expectEmit();
        emit Hookable.HookBitmapsSet(beforeBitmap, afterBitmap, newBeforeBitmap, newAfterBitmap);

        vm.prank(hookUpdater);
        hookable.setHookBitmaps(newBeforeBitmap, newAfterBitmap);

        (uint256 configuredBeforeBitmap, uint256 configuredAfterBitmap) = hookable.hookBitmaps();
        assertEq(configuredBeforeBitmap, newBeforeBitmap);
        assertEq(configuredAfterBitmap, newAfterBitmap);
    }

    function test_setHookBitmaps_RevertsWhenCallerIsNotHookUpdater() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonHookUpdater, hookable.HOOK_UPDATER_ROLE()
            )
        );
        vm.prank(nonHookUpdater);
        hookable.setHookBitmaps(_bit(5), _bit(7));
    }

    // _fireHook()

    function test_fireHook_DoesNotRevertWhenHookReceiverIsNotSet() public {
        assertEq(hookable.hookReceiver(), address(0));

        hookable.fireHook(Phase.BEFORE, 5, abi.encode("hook data"));

        assertEq(hookable.hookReceiver(), address(0));
    }

    function test_fireHook_DoesNotCallReceiverWhenActionBitIsDisabled() public {
        vm.prank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));

        hookable.fireHook(Phase.BEFORE, 5, abi.encode("hook data"));

        assertEq(hookReceiver.calls(), 0);
    }

    function test_fireHook_CallsHookReceiverWhenBeforeActionBitIsEnabled() public {
        uint8 action = 5;
        bytes memory data = abi.encode("before hook data");

        vm.startPrank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));
        hookable.setHookBitmaps(_bit(action), 0);
        vm.stopPrank();

        hookable.fireHook(Phase.BEFORE, action, data);

        assertEq(hookReceiver.calls(), 1);
        assertEq(hookReceiver.lastHookSource(), address(hookable));
        assertEq(uint256(hookReceiver.lastPhase()), uint256(Phase.BEFORE));
        assertEq(hookReceiver.lastAction(), action);
        assertEq(hookReceiver.lastData(), data);
    }

    function test_fireHook_CallsHookReceiverWhenAfterActionBitIsEnabled() public {
        uint8 action = 7;
        bytes memory data = abi.encode("after hook data");

        vm.startPrank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));
        hookable.setHookBitmaps(0, _bit(action));
        vm.stopPrank();

        hookable.fireHook(Phase.AFTER, action, data);

        assertEq(hookReceiver.calls(), 1);
        assertEq(hookReceiver.lastHookSource(), address(hookable));
        assertEq(uint256(hookReceiver.lastPhase()), uint256(Phase.AFTER));
        assertEq(hookReceiver.lastAction(), action);
        assertEq(hookReceiver.lastData(), data);
    }

    function test_fireHook_DoesNotUseAfterBitmapForBeforeHooks() public {
        uint8 action = 5;

        vm.startPrank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));
        hookable.setHookBitmaps(0, _bit(action));
        vm.stopPrank();

        hookable.fireHook(Phase.BEFORE, action, abi.encode("hook data"));

        assertEq(hookReceiver.calls(), 0);
    }

    function test_fireHook_DoesNotUseBeforeBitmapForAfterHooks() public {
        uint8 action = 7;

        vm.startPrank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));
        hookable.setHookBitmaps(_bit(action), 0);
        vm.stopPrank();

        hookable.fireHook(Phase.AFTER, action, abi.encode("hook data"));

        assertEq(hookReceiver.calls(), 0);
    }

    function test_fireHook_PropagatesHookReceiverRevert() public {
        uint8 action = 5;

        vm.startPrank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));
        hookable.setHookBitmaps(_bit(action), 0);
        vm.stopPrank();

        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        hookable.fireHook(Phase.BEFORE, action, abi.encode("hook data"));
    }

    function _bit(uint8 action) internal pure returns (uint256) {
        return uint256(1) << action;
    }
}
