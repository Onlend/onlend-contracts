// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {Whitelistable} from "src/whitelist/abstract/Whitelistable.sol";
import {WhitelistConditionFactory} from "src/factories/pool/irm/modules/condition/WhitelistConditionFactory.sol";
import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {WhitelistCondition} from "src/pool/irm/modules/condition/WhitelistCondition.sol";

contract WhitelistConditionFactoryUnitTest is Test {
    WhitelistConditionFactory internal factory;
    WhitelistCondition internal implementation;

    address internal defaultAdmin = makeAddr("defaultAdmin");
    address internal whitelistConfigurator = makeAddr("whitelistConfigurator");
    address internal account = makeAddr("account");

    bytes32 internal constant SALT = keccak256("salt");

    function setUp() public {
        implementation = new WhitelistCondition();
        factory = new WhitelistConditionFactory(address(implementation));
    }

    // clone()

    function test_Clone_InitializesCloneWithDecodedRolesAndAccounts() public {
        Whitelistable.WhitelistUpdate[] memory updates = _updates();

        address instance = factory.clone(SALT, abi.encode(defaultAdmin, whitelistConfigurator, updates));

        WhitelistCondition whitelistCondition = WhitelistCondition(instance);
        assertTrue(whitelistCondition.hasRole(whitelistCondition.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(whitelistCondition.hasRole(whitelistCondition.WHITELIST_CONFIG_ROLE(), whitelistConfigurator));
        assertTrue(whitelistCondition.isWhitelisted(account));
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit(address(factory));
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, abi.encode(defaultAdmin, whitelistConfigurator, _updates()));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "WhitelistCondition1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    function _updates() internal view returns (Whitelistable.WhitelistUpdate[] memory updates) {
        updates = new Whitelistable.WhitelistUpdate[](1);
        updates[0] = Whitelistable.WhitelistUpdate({account: account, isWhitelisted: true});
    }
}
