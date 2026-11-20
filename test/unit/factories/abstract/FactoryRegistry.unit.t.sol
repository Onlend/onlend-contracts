// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {FactoryRegistry} from "src/factories/abstract/FactoryRegistry.sol";
import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {FactoryLib} from "src/factories/lib/FactoryLib.sol";
import {FactoryRegistryHarness} from "./mocks/FactoryRegistryHarness.sol";
import {MockCloneFactory} from "./mocks/MockCloneFactory.sol";

contract FactoryRegistryTest is Test {
    FactoryRegistryHarness registry;
    MockCloneFactory cloneFactoryA;
    MockCloneFactory cloneFactoryB;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");

    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        registry = new FactoryRegistryHarness(owner);
        cloneFactoryA = new MockCloneFactory();
        cloneFactoryB = new MockCloneFactory();
    }

    // constructor()

    function test_Constructor_SetsOwner() public view {
        assertEq(registry.owner(), owner);
    }

    function test_Constructor_Revert_ZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new FactoryRegistryHarness(address(0));
    }

    // registerCloneFactory()

    function test_RegisterCloneFactory_RegistersFactory() public {
        vm.prank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));

        assertTrue(registry.isCloneFactory(address(cloneFactoryA)));
    }

    function test_RegisterCloneFactory_AddsFactoryToCloneFactoriesList() public {
        vm.prank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));

        address[] memory list = registry.cloneFactories();

        assertEq(list.length, 1);
        assertEq(list[0], address(cloneFactoryA));
    }

    function test_RegisterCloneFactory_EmitsCloneFactoryRegistered() public {
        vm.expectEmit();
        emit FactoryRegistry.CloneFactoryRegistered(address(cloneFactoryA));
        vm.prank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));
    }

    function test_RegisterCloneFactory_Revert_NotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        registry.registerCloneFactory(address(cloneFactoryA));
    }

    function test_RegisterCloneFactory_Revert_AlreadyRegistered() public {
        vm.startPrank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));

        vm.expectRevert(
            abi.encodeWithSelector(FactoryRegistry.CloneFactoryAlreadyRegistered.selector, address(cloneFactoryA))
        );
        registry.registerCloneFactory(address(cloneFactoryA));
        vm.stopPrank();
    }

    function test_RegisterCloneFactory_Revert_NotContract() public {
        vm.expectRevert(FactoryRegistry.CloneFactoryNotContract.selector);
        vm.prank(owner);
        registry.registerCloneFactory(alice);
    }

    // removeCloneFactory()

    function test_RemoveCloneFactory_RemovesFactory() public {
        vm.startPrank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));

        registry.removeCloneFactory(address(cloneFactoryA));
        vm.stopPrank();

        assertFalse(registry.isCloneFactory(address(cloneFactoryA)));
        assertEq(registry.cloneFactories().length, 0);
    }

    function test_RemoveCloneFactory_EmitsCloneFactoryRemoved() public {
        vm.startPrank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));

        vm.expectEmit();
        emit FactoryRegistry.CloneFactoryRemoved(address(cloneFactoryA));
        registry.removeCloneFactory(address(cloneFactoryA));
        vm.stopPrank();
    }

    function test_RemoveCloneFactory_AllowsReRegistration() public {
        vm.startPrank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));
        registry.removeCloneFactory(address(cloneFactoryA));

        registry.registerCloneFactory(address(cloneFactoryA));
        vm.stopPrank();

        assertTrue(registry.isCloneFactory(address(cloneFactoryA)));
    }

    function test_RemoveCloneFactory_Revert_NotOwner() public {
        vm.prank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        registry.removeCloneFactory(address(cloneFactoryA));
    }

    function test_RemoveCloneFactory_Revert_NotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(FactoryRegistry.CloneFactoryNotRegistered.selector, address(cloneFactoryA))
        );
        vm.prank(owner);
        registry.removeCloneFactory(address(cloneFactoryA));
    }

    // isCloneFactory()

    function test_IsCloneFactory_ReturnsFalseInitially() public view {
        assertFalse(registry.isCloneFactory(address(cloneFactoryA)));
    }

    function test_IsCloneFactory_ReturnsTrueAfterRegistration() public {
        vm.prank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));

        assertTrue(registry.isCloneFactory(address(cloneFactoryA)));
    }

    // cloneFactories()

    function test_CloneFactories_ReturnsEmptyArrayInitially() public view {
        assertEq(registry.cloneFactories().length, 0);
    }

    function test_CloneFactories_ReturnsAllRegisteredFactories() public {
        vm.startPrank(owner);
        registry.registerCloneFactory(address(cloneFactoryB));
        registry.registerCloneFactory(address(cloneFactoryA));
        vm.stopPrank();

        address[] memory list = registry.cloneFactories();

        assertEq(list.length, 2);
        assertEq(list[0], address(cloneFactoryB));
        assertEq(list[1], address(cloneFactoryA));
    }

    // cloneFactoriesLength()

    function test_CloneFactoriesLength_ReturnsZeroInitially() public view {
        assertEq(registry.cloneFactoriesLength(), 0);
    }

    function test_CloneFactoriesLength_ReturnsCountOfRegisteredFactories() public {
        vm.startPrank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));
        registry.registerCloneFactory(address(cloneFactoryB));
        vm.stopPrank();

        assertEq(registry.cloneFactoriesLength(), 2);
    }

    // cloneFactoryAt()

    function test_CloneFactoryAt_ReturnsFactoryAtIndex() public {
        vm.startPrank(owner);
        registry.registerCloneFactory(address(cloneFactoryB));
        registry.registerCloneFactory(address(cloneFactoryA));
        vm.stopPrank();

        assertEq(registry.cloneFactoryAt(0), address(cloneFactoryB));
        assertEq(registry.cloneFactoryAt(1), address(cloneFactoryA));
    }

    function test_CloneFactoryAt_Revert_OutOfBounds() public {
        vm.expectRevert();
        registry.cloneFactoryAt(0);
    }

    // predictAddress()

    function test_PredictAddress_RoutesToRegisteredCloneFactory() public {
        address expectedPredicted = makeAddr("predicted");
        cloneFactoryA.setPredictReturn(expectedPredicted);

        vm.prank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));

        vm.expectCall(
            address(cloneFactoryA),
            abi.encodeCall(ICloneFactory.predictAddress, (address(registry), FactoryLib.callerSalt(alice, SALT)))
        );
        address predicted = registry.predictAddress(address(cloneFactoryA), alice, SALT);

        assertEq(predicted, expectedPredicted);
    }

    function test_PredictAddress_Revert_NotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(FactoryRegistry.CloneFactoryNotRegistered.selector, address(cloneFactoryA))
        );
        registry.predictAddress(address(cloneFactoryA), alice, SALT);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(registry.contractName(), "FactoryRegistryHarness");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(registry.contractVersion(), "1.0.0");
    }

    // _clone()

    function test_Clone_RoutesToRegisteredCloneFactory() public {
        address expectedInstance = makeAddr("instance");
        cloneFactoryA.setCloneReturn(expectedInstance);

        vm.prank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));

        vm.expectCall(
            address(cloneFactoryA),
            abi.encodeCall(ICloneFactory.clone, (FactoryLib.callerSalt(address(this), SALT), ""))
        );
        address instance = registry.exposedClone(address(cloneFactoryA), SALT, "");

        assertEq(instance, expectedInstance);
    }

    function test_Clone_DifferentFactoriesRouteIndependently() public {
        address instanceA = makeAddr("instanceA");
        address instanceB = makeAddr("instanceB");
        cloneFactoryA.setCloneReturn(instanceA);
        cloneFactoryB.setCloneReturn(instanceB);

        vm.startPrank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));
        registry.registerCloneFactory(address(cloneFactoryB));
        vm.stopPrank();

        assertEq(registry.exposedClone(address(cloneFactoryA), SALT, ""), instanceA);
        assertEq(registry.exposedClone(address(cloneFactoryB), SALT, ""), instanceB);
    }

    function test_Clone_Revert_NotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(FactoryRegistry.CloneFactoryNotRegistered.selector, address(cloneFactoryA))
        );
        registry.exposedClone(address(cloneFactoryA), SALT, "");
    }

    function test_Clone_Revert_AfterRemoval() public {
        vm.startPrank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));
        registry.removeCloneFactory(address(cloneFactoryA));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(FactoryRegistry.CloneFactoryNotRegistered.selector, address(cloneFactoryA))
        );
        registry.exposedClone(address(cloneFactoryA), SALT, "");
    }
}
