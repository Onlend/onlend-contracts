// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {FactoryRegistry} from "src/factories/abstract/FactoryRegistry.sol";
import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {FactoryLib} from "src/factories/lib/FactoryLib.sol";
import {FactoryRegistryHarness} from "./mocks/FactoryRegistryHarness.sol";
import {MockCloneFactory} from "./mocks/MockCloneFactory.sol";

contract FactoryRegistryFuzzTest is Test {
    FactoryRegistryHarness registry;
    MockCloneFactory cloneFactoryA;

    address owner = makeAddr("owner");

    function setUp() public {
        registry = new FactoryRegistryHarness(owner);
        cloneFactoryA = new MockCloneFactory();
    }

    // registerCloneFactory()

    function testFuzz_RegisterCloneFactory_RegistersFactory(address cloneFactory) public {
        assumeNotPrecompile(cloneFactory);
        vm.assume(cloneFactory.code.length == 0);
        MockCloneFactory realFactory = new MockCloneFactory();
        vm.etch(cloneFactory, address(realFactory).code);

        vm.prank(owner);
        registry.registerCloneFactory(cloneFactory);

        assertTrue(registry.isCloneFactory(cloneFactory));
    }

    function testFuzz_RegisterCloneFactory_Revert_AlreadyRegistered(address first) public {
        assumeNotPrecompile(first);
        vm.assume(first.code.length == 0);
        MockCloneFactory realFactory = new MockCloneFactory();
        vm.etch(first, address(realFactory).code);

        vm.startPrank(owner);
        registry.registerCloneFactory(first);

        vm.expectRevert(abi.encodeWithSelector(FactoryRegistry.CloneFactoryAlreadyRegistered.selector, first));
        registry.registerCloneFactory(first);
        vm.stopPrank();
    }

    function testFuzz_RegisterCloneFactory_Revert_NotContract(address notContract) public {
        vm.assume(notContract.code.length == 0);

        vm.expectRevert(FactoryRegistry.CloneFactoryNotContract.selector);
        vm.prank(owner);
        registry.registerCloneFactory(notContract);
    }

    // predictAddress()

    function testFuzz_PredictAddress_RoutesToRegisteredCloneFactory(address caller, bytes32 salt, address predicted)
        public
    {
        cloneFactoryA.setPredictReturn(predicted);
        vm.prank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));

        vm.expectCall(
            address(cloneFactoryA),
            abi.encodeCall(ICloneFactory.predictAddress, (address(registry), FactoryLib.callerSalt(caller, salt)))
        );
        address result = registry.predictAddress(address(cloneFactoryA), caller, salt);

        assertEq(result, predicted);
    }

    // _clone()

    function testFuzz_Clone_RoutesToRegisteredCloneFactory(address caller, bytes32 salt, address instance) public {
        vm.assume(caller != address(0));
        cloneFactoryA.setCloneReturn(instance);
        vm.prank(owner);
        registry.registerCloneFactory(address(cloneFactoryA));

        vm.expectCall(
            address(cloneFactoryA), abi.encodeCall(ICloneFactory.clone, (FactoryLib.callerSalt(caller, salt), ""))
        );
        vm.prank(caller);
        address result = registry.exposedClone(address(cloneFactoryA), salt, "");

        assertEq(result, instance);
    }

    function testFuzz_Clone_Revert_NotRegistered(address cloneFactory, bytes32 salt) public {
        vm.expectRevert(abi.encodeWithSelector(FactoryRegistry.CloneFactoryNotRegistered.selector, cloneFactory));
        registry.exposedClone(cloneFactory, salt, "");
    }
}
