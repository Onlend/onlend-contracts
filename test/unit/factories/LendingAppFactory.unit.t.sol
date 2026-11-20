// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {LendingAppFactory} from "src/factories/LendingAppFactory.sol";
import {ILendingAppFactory} from "src/factories/interfaces/ILendingAppFactory.sol";
import {FactoryRegistry} from "src/factories/abstract/FactoryRegistry.sol";
import {MockCloneFactory} from "./abstract/mocks/MockCloneFactory.sol";
import {CloneFactoryHarness} from "./abstract/mocks/CloneFactoryHarness.sol";
import {MockImplementation} from "./abstract/mocks/MockImplementation.sol";

contract LendingAppFactoryTest is Test {
    LendingAppFactory factory;
    MockCloneFactory cloneFactoryA;
    MockCloneFactory cloneFactoryB;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");

    bytes32 constant SALT = keccak256("salt");
    bytes32 constant SALT_B = keccak256("salt-b");

    function setUp() public {
        factory = new LendingAppFactory(owner);
        cloneFactoryA = new MockCloneFactory();
        cloneFactoryB = new MockCloneFactory();
    }

    // constructor()

    function test_Constructor_SetsOwner() public view {
        assertEq(factory.owner(), owner);
    }

    function test_Constructor_Revert_ZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new LendingAppFactory(address(0));
    }

    // deploy()

    function test_deploy_ReturnsEmptyArrayForEmptyInput() public {
        ILendingAppFactory.ModuleConfig[] memory modules = new ILendingAppFactory.ModuleConfig[](0);

        ILendingAppFactory.DeployedModule[] memory deployed = factory.deploy(modules);

        assertEq(deployed.length, 0);
    }

    function test_deploy_DeploysSingleModule() public {
        address expectedInstance = makeAddr("instance");
        cloneFactoryA.setCloneReturn(expectedInstance);
        vm.prank(owner);
        factory.registerCloneFactory(address(cloneFactoryA));
        ILendingAppFactory.ModuleConfig[] memory modules = _singleConfig(address(cloneFactoryA), SALT, "");

        ILendingAppFactory.DeployedModule[] memory deployed = factory.deploy(modules);

        assertEq(deployed.length, 1);
        assertEq(deployed[0].cloneFactory, address(cloneFactoryA));
        assertEq(deployed[0].instance, expectedInstance);
    }

    function test_deploy_EmitsModuleDeployedEvent() public {
        address expectedInstance = makeAddr("instance");
        cloneFactoryA.setCloneReturn(expectedInstance);
        vm.prank(owner);
        factory.registerCloneFactory(address(cloneFactoryA));
        ILendingAppFactory.ModuleConfig[] memory modules = _singleConfig(address(cloneFactoryA), SALT, "");

        vm.expectEmit(address(factory));
        emit ILendingAppFactory.ModuleDeployed(alice, address(cloneFactoryA), expectedInstance);
        vm.prank(alice);
        factory.deploy(modules);
    }

    function test_deploy_DeploysMultipleModulesInOrder() public {
        address instanceA = makeAddr("instanceA");
        address instanceB = makeAddr("instanceB");
        cloneFactoryA.setCloneReturn(instanceA);
        cloneFactoryB.setCloneReturn(instanceB);
        vm.startPrank(owner);
        factory.registerCloneFactory(address(cloneFactoryA));
        factory.registerCloneFactory(address(cloneFactoryB));
        vm.stopPrank();
        ILendingAppFactory.ModuleConfig[] memory modules = new ILendingAppFactory.ModuleConfig[](2);
        modules[0] = ILendingAppFactory.ModuleConfig({cloneFactory: address(cloneFactoryB), salt: SALT, data: ""});
        modules[1] = ILendingAppFactory.ModuleConfig({cloneFactory: address(cloneFactoryA), salt: SALT, data: ""});

        ILendingAppFactory.DeployedModule[] memory deployed = factory.deploy(modules);

        assertEq(deployed.length, 2);
        assertEq(deployed[0].cloneFactory, address(cloneFactoryB));
        assertEq(deployed[0].instance, instanceB);
        assertEq(deployed[1].cloneFactory, address(cloneFactoryA));
        assertEq(deployed[1].instance, instanceA);
    }

    function test_deploy_SameCloneFactoryDifferentSaltsDoNotCollide() public {
        CloneFactoryHarness realFactory = new CloneFactoryHarness(address(new MockImplementation()));
        vm.prank(owner);
        factory.registerCloneFactory(address(realFactory));
        ILendingAppFactory.ModuleConfig[] memory modules = new ILendingAppFactory.ModuleConfig[](2);
        modules[0] = ILendingAppFactory.ModuleConfig({cloneFactory: address(realFactory), salt: SALT, data: ""});
        modules[1] = ILendingAppFactory.ModuleConfig({cloneFactory: address(realFactory), salt: SALT_B, data: ""});

        ILendingAppFactory.DeployedModule[] memory deployed = factory.deploy(modules);

        assertNotEq(deployed[0].instance, deployed[1].instance);
    }

    function test_deploy_PredictAddressMatchesDeployedInstance() public {
        CloneFactoryHarness realFactory = new CloneFactoryHarness(address(new MockImplementation()));
        vm.prank(owner);
        factory.registerCloneFactory(address(realFactory));
        ILendingAppFactory.ModuleConfig[] memory modules = _singleConfig(address(realFactory), SALT, "");
        address predicted = factory.predictAddress(address(realFactory), alice, SALT);

        vm.prank(alice);
        ILendingAppFactory.DeployedModule[] memory deployed = factory.deploy(modules);

        assertEq(deployed[0].instance, predicted);
    }

    function test_deploy_Revert_CloneFactoryNotRegistered() public {
        ILendingAppFactory.ModuleConfig[] memory modules = _singleConfig(address(cloneFactoryA), SALT, "");

        vm.expectRevert(
            abi.encodeWithSelector(FactoryRegistry.CloneFactoryNotRegistered.selector, address(cloneFactoryA))
        );
        factory.deploy(modules);
    }

    function test_deploy_Revert_PartialFailureRevertsWholeBatch() public {
        vm.prank(owner);
        factory.registerCloneFactory(address(cloneFactoryA));
        ILendingAppFactory.ModuleConfig[] memory modules = new ILendingAppFactory.ModuleConfig[](2);
        modules[0] = ILendingAppFactory.ModuleConfig({cloneFactory: address(cloneFactoryA), salt: SALT, data: ""});
        modules[1] = ILendingAppFactory.ModuleConfig({cloneFactory: address(cloneFactoryB), salt: SALT, data: ""});

        vm.expectRevert(
            abi.encodeWithSelector(FactoryRegistry.CloneFactoryNotRegistered.selector, address(cloneFactoryB))
        );
        factory.deploy(modules);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "LendingAppFactory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    // Helpers

    function _singleConfig(address cloneFactory_, bytes32 salt, bytes memory data)
        internal
        pure
        returns (ILendingAppFactory.ModuleConfig[] memory modules)
    {
        modules = new ILendingAppFactory.ModuleConfig[](1);
        modules[0] = ILendingAppFactory.ModuleConfig({cloneFactory: cloneFactory_, salt: salt, data: data});
    }
}
