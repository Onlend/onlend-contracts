// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {PauseHookReceiverFactory} from "src/factories/hooks/modules/PauseHookReceiverFactory.sol";
import {PauseHookReceiver} from "src/hooks/modules/PauseHookReceiver.sol";

contract PauseHookReceiverFactoryUnitTest is Test {
    PauseHookReceiverFactory factory;
    PauseHookReceiver implementation;

    address defaultAdmin = makeAddr("defaultAdmin");
    address pauseConfigurator = makeAddr("pauseConfigurator");
    address unpauseConfigurator = makeAddr("unpauseConfigurator");

    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        implementation = new PauseHookReceiver();
        factory = new PauseHookReceiverFactory(address(implementation));
    }

    // clone()

    function test_Clone_InitializesCloneWithDecodedRoles() public {
        address instance = factory.clone(SALT, abi.encode(defaultAdmin, _pauseConfigurators(), unpauseConfigurator));

        PauseHookReceiver pauseHookReceiver = PauseHookReceiver(instance);
        assertTrue(pauseHookReceiver.hasRole(pauseHookReceiver.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(pauseHookReceiver.hasRole(pauseHookReceiver.PAUSE_CONFIG_ROLE(), pauseConfigurator));
        assertTrue(pauseHookReceiver.hasRole(pauseHookReceiver.UNPAUSE_CONFIG_ROLE(), unpauseConfigurator));
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, abi.encode(defaultAdmin, _pauseConfigurators(), unpauseConfigurator));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "PauseHookReceiver1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    // Helpers

    function _pauseConfigurators() internal view returns (address[] memory pauseConfigurators) {
        pauseConfigurators = new address[](1);
        pauseConfigurators[0] = pauseConfigurator;
    }
}
