// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {MultiHookReceiver} from "src/hooks/MultiHookReceiver.sol";
import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {MockHookReceiver} from "./mocks/MockHookReceiver.sol";

contract MultiHookReceiverFuzzTest is Test {
    address internal hookReceiversUpdater;
    address internal hookCaller;
    MultiHookReceiver internal implementation;
    MultiHookReceiver internal multiHookReceiver;
    MockHookReceiver internal firstHookReceiver;
    MockHookReceiver internal secondHookReceiver;

    function setUp() public {
        hookReceiversUpdater = makeAddr("hookReceiversUpdater");
        hookCaller = makeAddr("hookCaller");
        implementation = new MultiHookReceiver();

        multiHookReceiver = MultiHookReceiver(Clones.clone(address(implementation)));
        multiHookReceiver.initialize(
            makeAddr("defaultAdmin"),
            hookReceiversUpdater,
            _hookCallers(),
            new MultiHookReceiver.HookReceiverConfig[](0)
        );
        firstHookReceiver = new MockHookReceiver();
        secondHookReceiver = new MockHookReceiver();
    }

    // initialize()

    function testFuzz_initialize_SetsInitialHookReceiverConfigs(uint8 phaseSeed, uint8 action) public {
        Phase phase = _phase(phaseSeed);
        address[] memory hookReceivers = _hookReceivers(address(firstHookReceiver), address(secondHookReceiver));
        MultiHookReceiver.HookReceiverConfig[] memory configs = _hookReceiverConfigs(phase, action, hookReceivers);
        MultiHookReceiver instance = MultiHookReceiver(Clones.clone(address(implementation)));

        instance.initialize(makeAddr("defaultAdmin"), hookReceiversUpdater, _hookCallers(), configs);

        assertEq(instance.getHookReceivers(phase, action), hookReceivers);
    }

    // setHookReceivers()

    function testFuzz_setHookReceivers_SetsHookReceiversForPhaseAndAction(uint8 phaseSeed, uint8 action) public {
        Phase phase = _phase(phaseSeed);
        address[] memory hookReceivers = _hookReceivers(address(firstHookReceiver), address(secondHookReceiver));

        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(_hookReceiverConfigs(phase, action, hookReceivers));

        assertEq(multiHookReceiver.getHookReceivers(phase, action), hookReceivers);
    }

    function testFuzz_setHookReceivers_SetsVariableLengthConfigs(
        uint8 phaseSeed,
        uint8 action,
        uint256 configsLength,
        uint256 hookReceiversSeed
    ) public {
        configsLength = bound(configsLength, 0, 5);
        MultiHookReceiver.HookReceiverConfig[] memory configs =
            new MultiHookReceiver.HookReceiverConfig[](configsLength);

        for (uint256 i = 0; i < configsLength; i++) {
            configs[i] = MultiHookReceiver.HookReceiverConfig({
                phase: _phaseAt(phaseSeed, i),
                action: _actionAt(action, i),
                hookReceivers: _validHookReceivers(hookReceiversSeed >> (i * 2))
            });
        }

        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(configs);

        for (uint256 i = 0; i < configsLength; i++) {
            assertEq(multiHookReceiver.getHookReceivers(configs[i].phase, configs[i].action), configs[i].hookReceivers);
        }
    }

    function testFuzz_setHookReceivers_RevertsWhenAnyVariableLengthConfigContainsInvalidHookReceiver(
        uint8 phaseSeed,
        uint8 action,
        uint256 configsLength,
        uint256 invalidConfigIndex
    ) public {
        configsLength = bound(configsLength, 2, 5);
        invalidConfigIndex = bound(invalidConfigIndex, 1, configsLength - 1);
        address invalidHookReceiver = makeAddr("invalidHookReceiver");
        MultiHookReceiver.HookReceiverConfig[] memory configs =
            new MultiHookReceiver.HookReceiverConfig[](configsLength);

        for (uint256 i = 0; i < configsLength; i++) {
            address[] memory hookReceivers = i == invalidConfigIndex
                ? _hookReceivers(invalidHookReceiver)
                : _hookReceivers(address(firstHookReceiver));
            configs[i] = MultiHookReceiver.HookReceiverConfig({
                phase: _phaseAt(phaseSeed, i), action: _actionAt(action, i), hookReceivers: hookReceivers
            });
        }

        vm.expectRevert(abi.encodeWithSelector(MultiHookReceiver.InvalidHookReceiver.selector, invalidHookReceiver));
        vm.prank(hookReceiversUpdater);
        multiHookReceiver.setHookReceivers(configs);

        for (uint256 i = 0; i < invalidConfigIndex; i++) {
            assertEq(multiHookReceiver.getHookReceivers(configs[i].phase, configs[i].action), new address[](0));
        }
    }

    // onHook()

    function testFuzz_onHook_CallsHookReceiversForConfiguredPhaseAndAction(
        uint8 phaseSeed,
        uint8 action,
        bytes32 dataSeed
    ) public {
        Phase phase = _phase(phaseSeed);
        bytes memory data = abi.encode(dataSeed);
        _setHookReceivers(phase, action, _hookReceivers(address(firstHookReceiver), address(secondHookReceiver)));

        vm.prank(hookCaller);
        multiHookReceiver.onHook(hookCaller, phase, action, data);

        assertEq(firstHookReceiver.calls(), 1);
        assertEq(firstHookReceiver.lastHookSource(), hookCaller);
        assertEq(uint256(firstHookReceiver.lastPhase()), uint256(phase));
        assertEq(firstHookReceiver.lastAction(), action);
        assertEq(firstHookReceiver.lastData(), data);

        assertEq(secondHookReceiver.calls(), 1);
        assertEq(secondHookReceiver.lastHookSource(), hookCaller);
        assertEq(uint256(secondHookReceiver.lastPhase()), uint256(phase));
        assertEq(secondHookReceiver.lastAction(), action);
        assertEq(secondHookReceiver.lastData(), data);
    }

    function testFuzz_onHook_DoesNotCallHookReceiversConfiguredForDifferentPhase(
        uint8 phaseSeed,
        uint8 action,
        bytes32 dataSeed
    ) public {
        Phase phase = _phase(phaseSeed);
        _setHookReceivers(phase, action, _hookReceivers(address(firstHookReceiver)));

        vm.prank(hookCaller);
        multiHookReceiver.onHook(hookCaller, _differentPhase(phase), action, abi.encode(dataSeed));

        assertEq(firstHookReceiver.calls(), 0);
    }

    function testFuzz_onHook_DoesNotCallHookReceiversConfiguredForDifferentAction(
        uint8 phaseSeed,
        uint8 action,
        bytes32 dataSeed
    ) public {
        Phase phase = _phase(phaseSeed);
        _setHookReceivers(phase, action, _hookReceivers(address(firstHookReceiver)));

        vm.prank(hookCaller);
        multiHookReceiver.onHook(hookCaller, phase, _differentAction(action), abi.encode(dataSeed));

        assertEq(firstHookReceiver.calls(), 0);
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
        hookCallers = new address[](1);
        hookCallers[0] = hookCaller;
    }

    function _validHookReceivers(uint256 receiverSeed) internal view returns (address[] memory hookReceivers) {
        uint256 hookReceiversLength = receiverSeed % 3;
        if (hookReceiversLength == 0) return new address[](0);
        if (hookReceiversLength == 1) return _hookReceivers(address(firstHookReceiver));
        return _hookReceivers(address(firstHookReceiver), address(secondHookReceiver));
    }

    function _phase(uint8 phaseSeed) internal pure returns (Phase) {
        return Phase(uint8(bound(uint256(phaseSeed), 0, 1)));
    }

    function _phaseAt(uint8 phaseSeed, uint256 offset) internal pure returns (Phase phase) {
        phase = _phase(phaseSeed);
        for (uint256 i = 0; i < offset; i++) {
            phase = _differentPhase(phase);
        }
    }

    function _differentPhase(Phase phase) internal pure returns (Phase) {
        return phase == Phase.BEFORE ? Phase.AFTER : Phase.BEFORE;
    }

    function _actionAt(uint8 action, uint256 offset) internal pure returns (uint8) {
        for (uint256 i = 0; i < offset; i++) {
            action = _differentAction(action);
        }
        return action;
    }

    function _differentAction(uint8 action) internal pure returns (uint8) {
        return action == type(uint8).max ? 0 : action + 1;
    }
}
