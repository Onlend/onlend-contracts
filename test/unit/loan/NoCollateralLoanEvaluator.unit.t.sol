// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILoanEvaluator} from "src/loan/interfaces/ILoanEvaluator.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {NoCollateralLoanEvaluator} from "src/loan/NoCollateralLoanEvaluator.sol";

import {LoanHelpers} from "../../helpers/LoanHelpers.sol";

contract NoCollateralLoanEvaluatorUnitTest is Test {
    NoCollateralLoanEvaluator implementation;
    NoCollateralLoanEvaluator evaluator;

    function setUp() public {
        implementation = new NoCollateralLoanEvaluator();
        evaluator = NoCollateralLoanEvaluator(Clones.clone(address(implementation)));
        evaluator.initialize();
    }

    // getLoanHealth()

    function test_getLoanHealth_ReturnsMaxWhenLoanIsEmpty() public view {
        uint256 health = evaluator.getLoanHealth(LoanHelpers.emptyLoan());

        assertEq(health, type(uint256).max);
    }

    function test_getLoanHealth_ReturnsMaxWhenLoanHasBorrow() public view {
        ILendingCore.Loan memory loan = LoanHelpers.loanWithSingleBorrow(address(0xACC0), IPool(address(0xB0)), 50e18);

        uint256 health = evaluator.getLoanHealth(loan);

        assertEq(health, type(uint256).max);
    }

    // isLoanHealthy()

    function test_isLoanHealthy_ReturnsTrueWhenLoanIsEmpty() public view {
        bool healthy = evaluator.isLoanHealthy(LoanHelpers.emptyLoan());

        assertTrue(healthy);
    }

    function test_isLoanHealthy_ReturnsTrueWhenLoanHasBorrow() public view {
        ILendingCore.Loan memory loan = LoanHelpers.loanWithSingleBorrow(address(0xACC0), IPool(address(0xB0)), 50e18);

        bool healthy = evaluator.isLoanHealthy(loan);

        assertTrue(healthy);
    }

    // isLoanLiquidatable()

    function test_isLoanLiquidatable_ReturnsFalseWhenLoanIsEmpty() public view {
        (bool liquidatable, uint256 health) = evaluator.isLoanLiquidatable(LoanHelpers.emptyLoan());

        assertFalse(liquidatable);
        assertEq(health, type(uint256).max);
    }

    function test_isLoanLiquidatable_ReturnsFalseWhenLoanHasBorrow() public view {
        ILendingCore.Loan memory loan = LoanHelpers.loanWithSingleBorrow(address(0xACC0), IPool(address(0xB0)), 50e18);

        (bool liquidatable, uint256 health) = evaluator.isLoanLiquidatable(loan);

        assertFalse(liquidatable);
        assertEq(health, type(uint256).max);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(evaluator.contractName(), "NoCollateralLoanEvaluator");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(evaluator.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_ReturnsTrueForILoanEvaluator() public view {
        assertTrue(evaluator.supportsInterface(type(ILoanEvaluator).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIVersioned() public view {
        assertTrue(evaluator.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIERC165() public view {
        assertTrue(evaluator.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_ReturnsFalseForUnknown() public view {
        assertFalse(evaluator.supportsInterface(0xffffffff));
        assertFalse(evaluator.supportsInterface(0xdeadbeef));
    }
}
