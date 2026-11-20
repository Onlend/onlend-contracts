// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {PauseHookReceiver} from "src/hooks/modules/PauseHookReceiver.sol";
import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";

contract PauseHookReceiverFuzzTest is Test {
    address internal pauseConfigurator;
    address internal unpauseConfigurator;
    address internal allSources;
    PauseHookReceiver internal implementation;
    PauseHookReceiver internal pauseHookReceiver;

    function setUp() public {
        pauseConfigurator = makeAddr("pauseConfigurator");
        unpauseConfigurator = makeAddr("unpauseConfigurator");
        implementation = new PauseHookReceiver();

        address[] memory pauseConfigurators = new address[](1);
        pauseConfigurators[0] = pauseConfigurator;
        pauseHookReceiver = PauseHookReceiver(Clones.clone(address(implementation)));
        pauseHookReceiver.initialize(makeAddr("defaultAdmin"), pauseConfigurators, unpauseConfigurator);
        allSources = pauseHookReceiver.ALL_SOURCES();
    }

    // pause()

    function testFuzz_pause_PausesActions(address hookSource, uint256 actions) public {
        vm.prank(pauseConfigurator);
        pauseHookReceiver.pause(hookSource, actions);

        assertEq(pauseHookReceiver.getPausedActions(hookSource), actions);
    }

    function testFuzz_pause_KeepsActionsAlreadyPaused(address hookSource, uint256 firstActions, uint256 secondActions)
        public
    {
        _pause(hookSource, firstActions);

        vm.prank(pauseConfigurator);
        pauseHookReceiver.pause(hookSource, secondActions);

        uint256 pausedActions = pauseHookReceiver.getPausedActions(hookSource);
        assertEq(pausedActions & firstActions, firstActions);
        assertEq(pausedActions & secondActions, secondActions);
    }

    // unpause()

    function testFuzz_unpause_ReversesPause(address hookSource, uint256 actions) public {
        _pause(hookSource, actions);

        vm.prank(unpauseConfigurator);
        pauseHookReceiver.unpause(hookSource, actions);

        assertEq(pauseHookReceiver.getPausedActions(hookSource), 0);
    }

    function testFuzz_unpause_IgnoresActionsNotPaused(address hookSource, uint256 pausedActions, uint256 actions)
        public
    {
        _pause(hookSource, pausedActions);

        vm.prank(unpauseConfigurator);
        pauseHookReceiver.unpause(hookSource, actions);

        uint256 remainingActions = pauseHookReceiver.getPausedActions(hookSource);
        assertEq(remainingActions & actions, 0);
        assertEq(remainingActions & ~actions, pausedActions & ~actions);
    }

    // onHook()

    function testFuzz_onHook_AllowsActionWhenEveryOtherActionIsPaused(address hookSource, uint8 action) public {
        _pause(hookSource, ~_bitmap(action));
        _pause(allSources, ~_bitmap(action));

        pauseHookReceiver.onHook(hookSource, Phase.BEFORE, action, "");
    }

    function testFuzz_onHook_AllowsActionPausedUnderDifferentHookSource(
        address hookSource,
        address otherHookSource,
        uint8 action
    ) public {
        vm.assume(hookSource != otherHookSource);
        vm.assume(otherHookSource != allSources);
        _pause(otherHookSource, _bitmap(action));

        pauseHookReceiver.onHook(hookSource, Phase.BEFORE, action, "");
    }

    function testFuzz_onHook_IgnoresHookDataWhenNotPaused(address hookSource, uint8 action, bytes calldata data)
        public
        view
    {
        pauseHookReceiver.onHook(hookSource, Phase.BEFORE, action, data);
    }

    function testFuzz_onHook_RevertsWhenActionIsPausedUnderHookSource(address hookSource, uint8 action) public {
        _pause(hookSource, _bitmap(action));

        vm.expectRevert(abi.encodeWithSelector(PauseHookReceiver.ActionPaused.selector, hookSource, action));
        pauseHookReceiver.onHook(hookSource, Phase.BEFORE, action, "");
    }

    function testFuzz_onHook_RevertsWhenActionIsPausedUnderAllSources(address hookSource, uint8 action) public {
        _pause(allSources, _bitmap(action));

        vm.expectRevert(abi.encodeWithSelector(PauseHookReceiver.ActionPaused.selector, hookSource, action));
        pauseHookReceiver.onHook(hookSource, Phase.BEFORE, action, "");
    }

    function testFuzz_onHook_IgnoresHookDataWhenPaused(address hookSource, uint8 action, bytes calldata data) public {
        _pause(hookSource, _bitmap(action));

        vm.expectRevert(abi.encodeWithSelector(PauseHookReceiver.ActionPaused.selector, hookSource, action));
        pauseHookReceiver.onHook(hookSource, Phase.BEFORE, action, data);
    }

    function _pause(address hookSource, uint256 actions) internal {
        vm.prank(pauseConfigurator);
        pauseHookReceiver.pause(hookSource, actions);
    }

    function _bitmap(uint8 action) internal pure returns (uint256) {
        return uint256(1) << action;
    }
}
