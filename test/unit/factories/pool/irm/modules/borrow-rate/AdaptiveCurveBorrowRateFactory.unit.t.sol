// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {
    AdaptiveCurveBorrowRateFactory
} from "src/factories/pool/irm/modules/borrow-rate/AdaptiveCurveBorrowRateFactory.sol";
import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {AdaptiveCurveBorrowRate} from "src/pool/irm/modules/borrow-rate/AdaptiveCurveBorrowRate.sol";

contract AdaptiveCurveBorrowRateFactoryUnitTest is Test {
    AdaptiveCurveBorrowRateFactory internal factory;
    AdaptiveCurveBorrowRate internal implementation;

    address internal borrowRateCaller = makeAddr("borrowRateCaller");

    bytes32 internal constant SALT = keccak256("salt");

    function setUp() public {
        implementation = new AdaptiveCurveBorrowRate();
        factory = new AdaptiveCurveBorrowRateFactory(address(implementation));
    }

    // clone()

    function test_Clone_InitializesCloneWithDecodedBorrowRateCaller() public {
        address instance = factory.clone(SALT, abi.encode(borrowRateCaller));

        assertEq(AdaptiveCurveBorrowRate(instance).borrowRateCaller(), borrowRateCaller);
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit(address(factory));
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, abi.encode(borrowRateCaller));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "AdaptiveCurveBorrowRate1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }
}
