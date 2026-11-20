// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {Whitelistable} from "src/whitelist/abstract/Whitelistable.sol";
import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {WhitelistHookReceiverFactory} from "src/factories/hooks/modules/WhitelistHookReceiverFactory.sol";
import {WhitelistHookReceiver} from "src/hooks/modules/WhitelistHookReceiver.sol";

contract WhitelistHookReceiverFactoryUnitTest is Test {
    WhitelistHookReceiverFactory factory;
    WhitelistHookReceiver implementation;

    address defaultAdmin = makeAddr("defaultAdmin");
    address whitelistConfigurator = makeAddr("whitelistConfigurator");
    address account = makeAddr("account");

    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        implementation = new WhitelistHookReceiver();
        factory = new WhitelistHookReceiverFactory(address(implementation));
    }

    // clone()

    function test_Clone_InitializesCloneWithDecodedRolesAndAccounts() public {
        Whitelistable.WhitelistUpdate[] memory updates = _updates();

        address instance = factory.clone(SALT, abi.encode(defaultAdmin, whitelistConfigurator, updates));

        WhitelistHookReceiver whitelistHookReceiver = WhitelistHookReceiver(instance);
        assertTrue(whitelistHookReceiver.hasRole(whitelistHookReceiver.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(whitelistHookReceiver.hasRole(whitelistHookReceiver.WHITELIST_CONFIG_ROLE(), whitelistConfigurator));
        assertTrue(whitelistHookReceiver.isWhitelisted(account));
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, abi.encode(defaultAdmin, whitelistConfigurator, _updates()));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "WhitelistHookReceiver1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    // Helpers

    function _updates() internal view returns (Whitelistable.WhitelistUpdate[] memory updates) {
        updates = new Whitelistable.WhitelistUpdate[](1);
        updates[0] = Whitelistable.WhitelistUpdate({account: account, isWhitelisted: true});
    }
}
