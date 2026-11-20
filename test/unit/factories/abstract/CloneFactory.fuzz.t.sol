// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {CloneFactoryHarness} from "./mocks/CloneFactoryHarness.sol";
import {MockImplementation} from "./mocks/MockImplementation.sol";

contract CloneFactoryFuzzTest is Test {
    CloneFactoryHarness factory;

    address implementation;

    function setUp() public {
        implementation = address(new MockImplementation());
        factory = new CloneFactoryHarness(implementation);
    }

    // clone() / predictAddress()

    function testFuzz_PredictAddress_MatchesClonedInstance(address caller, bytes32 salt) public {
        vm.assume(caller != address(0));

        address predicted = factory.predictAddress(caller, salt);

        vm.prank(caller);
        address instance = factory.clone(salt, "");

        assertEq(instance, predicted);
    }

    function testFuzz_Clone_DifferentCallersSameSaltDoNotCollide(address callerA, address callerB, bytes32 salt)
        public
    {
        vm.assume(callerA != address(0) && callerB != address(0));
        vm.assume(callerA != callerB);

        vm.prank(callerA);
        address instanceA = factory.clone(salt, "");

        vm.prank(callerB);
        address instanceB = factory.clone(salt, "");

        assertNotEq(instanceA, instanceB);
    }
}
