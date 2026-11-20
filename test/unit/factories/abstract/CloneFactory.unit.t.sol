// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";

import {CloneFactory} from "src/factories/abstract/CloneFactory.sol";
import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {CloneFactoryHarness} from "./mocks/CloneFactoryHarness.sol";
import {MockImplementation} from "./mocks/MockImplementation.sol";

contract CloneFactoryTest is Test {
    CloneFactoryHarness factory;

    address implementation;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        implementation = address(new MockImplementation());
        factory = new CloneFactoryHarness(implementation);
    }

    // constructor()

    function test_Constructor_Revert_ImplementationNotContract() public {
        vm.expectRevert(CloneFactory.ImplementationNotContract.selector);
        new CloneFactoryHarness(alice);
    }

    // clone()

    function test_Clone_DeploysContractCode() public {
        address instance = factory.clone(SALT, "");

        assertGt(instance.code.length, 0);
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = _predict(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, "");
    }

    function test_Clone_DifferentCallersSameSaltDoNotCollide() public {
        vm.prank(alice);
        address instanceA = factory.clone(SALT, "");

        vm.prank(bob);
        address instanceB = factory.clone(SALT, "");

        assertNotEq(instanceA, instanceB);
    }

    function test_Clone_Revert_SaltAlreadyUsed() public {
        factory.clone(SALT, "");

        vm.expectRevert(Errors.FailedDeployment.selector);
        factory.clone(SALT, "");
    }

    // IMPLEMENTATION()

    function test_Implementation_ReturnsConstructorValue() public view {
        assertEq(factory.IMPLEMENTATION(), implementation);
    }

    // predictAddress()

    function test_PredictAddress_MatchesClonedInstance() public {
        address predicted = factory.predictAddress(address(this), SALT);

        address instance = factory.clone(SALT, "");

        assertEq(instance, predicted);
    }

    function test_PredictAddress_DiffersByCaller() public view {
        address predictedAlice = factory.predictAddress(alice, SALT);
        address predictedBob = factory.predictAddress(bob, SALT);

        assertNotEq(predictedAlice, predictedBob);
    }

    function test_PredictAddress_DiffersBySalt() public view {
        address predictedFirst = factory.predictAddress(alice, SALT);
        address predictedSecond = factory.predictAddress(alice, keccak256("other salt"));

        assertNotEq(predictedFirst, predictedSecond);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "CloneFactoryHarness");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    // Helpers

    function _predict(address caller, bytes32 salt) internal view returns (address) {
        return Clones.predictDeterministicAddress(implementation, keccak256(abi.encode(caller, salt)), address(factory));
    }
}
