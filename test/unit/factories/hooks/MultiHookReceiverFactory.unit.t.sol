// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {MultiHookReceiverFactory} from "src/factories/hooks/MultiHookReceiverFactory.sol";
import {MultiHookReceiver} from "src/hooks/MultiHookReceiver.sol";
import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {MockHookReceiver} from "../../hooks/mocks/MockHookReceiver.sol";

contract MultiHookReceiverFactoryUnitTest is Test {
    MultiHookReceiverFactory factory;
    MultiHookReceiver implementation;
    MockHookReceiver hookReceiver;

    address defaultAdmin = makeAddr("defaultAdmin");
    address hookReceiversUpdater = makeAddr("hookReceiversUpdater");
    address hookCaller = makeAddr("hookCaller");

    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        implementation = new MultiHookReceiver();
        factory = new MultiHookReceiverFactory(address(implementation));
        hookReceiver = new MockHookReceiver();
    }

    // clone()

    function test_Clone_InitializesCloneWithDecodedRolesAndConfigs() public {
        MultiHookReceiver.HookReceiverConfig[] memory configs = _configs();

        address instance = factory.clone(SALT, abi.encode(defaultAdmin, hookReceiversUpdater, _hookCallers(), configs));

        MultiHookReceiver multiHookReceiver = MultiHookReceiver(instance);
        assertTrue(multiHookReceiver.hasRole(multiHookReceiver.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(multiHookReceiver.hasRole(multiHookReceiver.HOOK_RECEIVERS_UPDATER_ROLE(), hookReceiversUpdater));
        assertTrue(multiHookReceiver.hasRole(multiHookReceiver.HOOK_CALLER_ROLE(), hookCaller));
        assertEq(multiHookReceiver.getHookReceivers(Phase.BEFORE, 5).length, 1);
        assertEq(multiHookReceiver.getHookReceivers(Phase.BEFORE, 5)[0], address(hookReceiver));
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, abi.encode(defaultAdmin, hookReceiversUpdater, _hookCallers(), _configs()));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "MultiHookReceiver1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    // Helpers

    function _hookCallers() internal view returns (address[] memory hookCallers) {
        hookCallers = new address[](1);
        hookCallers[0] = hookCaller;
    }

    function _configs() internal view returns (MultiHookReceiver.HookReceiverConfig[] memory configs) {
        address[] memory hookReceivers = new address[](1);
        hookReceivers[0] = address(hookReceiver);

        configs = new MultiHookReceiver.HookReceiverConfig[](1);
        configs[0] =
            MultiHookReceiver.HookReceiverConfig({phase: Phase.BEFORE, action: 5, hookReceivers: hookReceivers});
    }
}
