// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {NoCollateralLoanEvaluatorFactory} from "src/factories/loan/NoCollateralLoanEvaluatorFactory.sol";
import {NoCollateralLoanEvaluator} from "src/loan/NoCollateralLoanEvaluator.sol";
import {LoanHelpers} from "../../../helpers/LoanHelpers.sol";

contract NoCollateralLoanEvaluatorFactoryUnitTest is Test {
    NoCollateralLoanEvaluatorFactory factory;
    NoCollateralLoanEvaluator implementation;

    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        implementation = new NoCollateralLoanEvaluator();
        factory = new NoCollateralLoanEvaluatorFactory(address(implementation));
    }

    // clone()

    function test_Clone_DeploysWorkingLoanEvaluator() public {
        address instance = factory.clone(SALT, "");

        NoCollateralLoanEvaluator evaluator = NoCollateralLoanEvaluator(instance);
        assertTrue(evaluator.isLoanHealthy(LoanHelpers.emptyLoan()));
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, "");
    }

    function test_Clone_RevertsWhenInitializationDataIsNotEmpty() public {
        vm.expectRevert(NoCollateralLoanEvaluatorFactory.UnexpectedInitializationData.selector);
        factory.clone(SALT, hex"01");
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "NoCollateralLoanEvaluator1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }
}
