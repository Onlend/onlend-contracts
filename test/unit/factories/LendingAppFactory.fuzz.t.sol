// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {LendingAppFactory} from "src/factories/LendingAppFactory.sol";
import {ILendingAppFactory} from "src/factories/interfaces/ILendingAppFactory.sol";
import {FactoryRegistry} from "src/factories/abstract/FactoryRegistry.sol";
import {MockCloneFactory} from "./abstract/mocks/MockCloneFactory.sol";
import {CloneFactoryHarness} from "./abstract/mocks/CloneFactoryHarness.sol";
import {MockImplementation} from "./abstract/mocks/MockImplementation.sol";

contract LendingAppFactoryFuzzTest is Test {
    LendingAppFactory factory;
    MockCloneFactory cloneFactory;
    CloneFactoryHarness realFactory;

    address owner = makeAddr("owner");

    function setUp() public {
        factory = new LendingAppFactory(owner);
        cloneFactory = new MockCloneFactory();
        realFactory = new CloneFactoryHarness(address(new MockImplementation()));
        vm.startPrank(owner);
        factory.registerCloneFactory(address(cloneFactory));
        factory.registerCloneFactory(address(realFactory));
        vm.stopPrank();
    }

    // deploy()

    function testFuzz_deploy_DeploysArbitraryNumberOfModules(uint8 count) public {
        count = uint8(bound(count, 1, 50));
        ILendingAppFactory.ModuleConfig[] memory modules = new ILendingAppFactory.ModuleConfig[](count);
        for (uint256 i = 0; i < count; i++) {
            modules[i] = ILendingAppFactory.ModuleConfig({
                cloneFactory: address(cloneFactory), salt: keccak256(abi.encode(i)), data: ""
            });
        }

        ILendingAppFactory.DeployedModule[] memory deployed = factory.deploy(modules);

        assertEq(deployed.length, count);
        for (uint256 i = 0; i < count; i++) {
            assertEq(deployed[i].cloneFactory, address(cloneFactory));
        }
    }

    function testFuzz_deploy_PredictAddressMatchesDeployedInstance(address caller, bytes32 salt) public {
        vm.assume(caller != address(0));
        address predicted = factory.predictAddress(address(realFactory), caller, salt);
        ILendingAppFactory.ModuleConfig[] memory modules = new ILendingAppFactory.ModuleConfig[](1);
        modules[0] = ILendingAppFactory.ModuleConfig({cloneFactory: address(realFactory), salt: salt, data: ""});

        vm.prank(caller);
        ILendingAppFactory.DeployedModule[] memory deployed = factory.deploy(modules);

        assertEq(deployed[0].instance, predicted);
    }

    function testFuzz_deploy_Revert_CloneFactoryNotRegistered(address unregistered) public {
        vm.assume(unregistered != address(cloneFactory) && unregistered != address(realFactory));
        ILendingAppFactory.ModuleConfig[] memory modules = new ILendingAppFactory.ModuleConfig[](1);
        modules[0] = ILendingAppFactory.ModuleConfig({cloneFactory: unregistered, salt: bytes32(0), data: ""});

        vm.expectRevert(abi.encodeWithSelector(FactoryRegistry.CloneFactoryNotRegistered.selector, unregistered));
        factory.deploy(modules);
    }
}
