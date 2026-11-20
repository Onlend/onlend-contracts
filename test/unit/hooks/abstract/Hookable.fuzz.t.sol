// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {HookableHarness} from "../mocks/HookableHarness.sol";
import {MockHookReceiver} from "../mocks/MockHookReceiver.sol";

contract HookableFuzzTest is Test {
    address internal hookUpdater;
    HookableHarness internal hookable;
    MockHookReceiver internal hookReceiver;

    function setUp() public {
        hookUpdater = makeAddr("hookUpdater");

        HookableHarness implementation = new HookableHarness();
        hookable = HookableHarness(Clones.clone(address(implementation)));
        hookable.initialize(makeAddr("defaultAdmin"), hookUpdater, address(0), 0, 0);
        hookReceiver = new MockHookReceiver();
    }

    // setHookBitmaps()

    function testFuzz_setHookBitmaps_SetsHookBitmaps(uint256 beforeBitmap, uint256 afterBitmap) public {
        vm.prank(hookUpdater);
        hookable.setHookBitmaps(beforeBitmap, afterBitmap);

        (uint256 configuredBeforeBitmap, uint256 configuredAfterBitmap) = hookable.hookBitmaps();
        assertEq(configuredBeforeBitmap, beforeBitmap);
        assertEq(configuredAfterBitmap, afterBitmap);
    }

    // _fireHook()

    function testFuzz_fireHook_CallsHookReceiverWhenBeforeActionBitIsEnabled(uint8 action, bytes32 dataSeed) public {
        bytes memory data = abi.encode(dataSeed);

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

    function testFuzz_fireHook_CallsHookReceiverWhenAfterActionBitIsEnabled(uint8 action, bytes32 dataSeed) public {
        bytes memory data = abi.encode(dataSeed);

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

    function testFuzz_fireHook_DoesNotCallReceiverWhenBeforeActionBitIsDisabled(
        uint8 action,
        uint256 beforeBitmap,
        bytes32 dataSeed
    ) public {
        beforeBitmap = beforeBitmap & ~_bit(action);

        vm.startPrank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));
        hookable.setHookBitmaps(beforeBitmap, 0);
        vm.stopPrank();

        hookable.fireHook(Phase.BEFORE, action, abi.encode(dataSeed));

        assertEq(hookReceiver.calls(), 0);
    }

    function testFuzz_fireHook_DoesNotCallReceiverWhenAfterActionBitIsDisabled(
        uint8 action,
        uint256 afterBitmap,
        bytes32 dataSeed
    ) public {
        afterBitmap = afterBitmap & ~_bit(action);

        vm.startPrank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));
        hookable.setHookBitmaps(0, afterBitmap);
        vm.stopPrank();

        hookable.fireHook(Phase.AFTER, action, abi.encode(dataSeed));

        assertEq(hookReceiver.calls(), 0);
    }

    function testFuzz_fireHook_DoesNotUseAfterBitmapForBeforeHooks(uint8 action, bytes32 dataSeed) public {
        vm.startPrank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));
        hookable.setHookBitmaps(0, _bit(action));
        vm.stopPrank();

        hookable.fireHook(Phase.BEFORE, action, abi.encode(dataSeed));

        assertEq(hookReceiver.calls(), 0);
    }

    function testFuzz_fireHook_DoesNotUseBeforeBitmapForAfterHooks(uint8 action, bytes32 dataSeed) public {
        vm.startPrank(hookUpdater);
        hookable.setHookReceiver(address(hookReceiver));
        hookable.setHookBitmaps(_bit(action), 0);
        vm.stopPrank();

        hookable.fireHook(Phase.AFTER, action, abi.encode(dataSeed));

        assertEq(hookReceiver.calls(), 0);
    }

    function _bit(uint8 action) internal pure returns (uint256) {
        return uint256(1) << action;
    }
}
