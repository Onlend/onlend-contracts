// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {FullLiquidationEngine} from "src/liquidation/FullLiquidationEngine.sol";
import {ILoanEvaluator} from "src/loan/interfaces/ILoanEvaluator.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";

import {LoanHelpers} from "../../helpers/LoanHelpers.sol";

contract FullLiquidationEngineFuzzTest is Test {
    // The engine never calls the evaluator, so a bare address suffices.
    ILoanEvaluator constant EVALUATOR = ILoanEvaluator(address(0xE7A));

    // The engine ignores the loan's health, so any value suffices.
    uint256 constant HEALTH = 0.5e18;

    address internal account;
    IPool internal collateralPool;
    IPool internal borrowPool;

    FullLiquidationEngine internal implementation;
    FullLiquidationEngine internal engine;

    function setUp() public {
        account = makeAddr("account");
        collateralPool = IPool(makeAddr("collateralPool"));
        borrowPool = IPool(makeAddr("borrowPool"));

        implementation = new FullLiquidationEngine();
        engine = FullLiquidationEngine(Clones.clone(address(implementation)));
        engine.initialize();
    }

    // liquidate()

    function testFuzz_liquidate_ReturnsLoanAmountsWhenRequestsAreWithinBounds(
        uint256 collateral,
        uint256 borrow,
        uint256 minCollateral,
        uint256 maxRepayment
    ) public view {
        minCollateral = bound(minCollateral, 0, collateral);
        maxRepayment = bound(maxRepayment, borrow, type(uint256).max);
        ILendingCore.Loan memory loan = _loan(collateral, borrow);

        (ILendingCore.LoanPosition[] memory colsToSeize, ILendingCore.LoanPosition[] memory borsToRepay) = engine.liquidate(
            loan,
            HEALTH,
            LoanHelpers.positions(collateralPool, minCollateral),
            LoanHelpers.positions(borrowPool, maxRepayment),
            EVALUATOR
        );

        assertEq(colsToSeize[0].amount, collateral);
        assertEq(borsToRepay[0].amount, borrow);
    }

    function testFuzz_liquidate_RevertsWhenCollateralIsBelowRequestedMinimum(
        uint256 collateral,
        uint256 borrow,
        uint256 minCollateral
    ) public {
        collateral = bound(collateral, 0, type(uint256).max - 1);
        minCollateral = bound(minCollateral, collateral + 1, type(uint256).max);
        ILendingCore.Loan memory loan = _loan(collateral, borrow);

        vm.expectRevert(
            abi.encodeWithSelector(
                FullLiquidationEngine.InsufficientCollateral.selector, collateralPool, minCollateral, collateral
            )
        );
        engine.liquidate(
            loan,
            HEALTH,
            LoanHelpers.positions(collateralPool, minCollateral),
            LoanHelpers.positions(borrowPool, borrow),
            EVALUATOR
        );
    }

    function testFuzz_liquidate_RevertsWhenBorrowIsAboveRequestedMaximum(
        uint256 collateral,
        uint256 borrow,
        uint256 maxRepayment
    ) public {
        borrow = bound(borrow, 1, type(uint256).max);
        maxRepayment = bound(maxRepayment, 0, borrow - 1);
        ILendingCore.Loan memory loan = _loan(collateral, borrow);

        vm.expectRevert(
            abi.encodeWithSelector(FullLiquidationEngine.ExcessiveRepayment.selector, borrowPool, maxRepayment, borrow)
        );
        engine.liquidate(
            loan,
            HEALTH,
            LoanHelpers.positions(collateralPool, collateral),
            LoanHelpers.positions(borrowPool, maxRepayment),
            EVALUATOR
        );
    }

    /// @dev A loan holding one collateral position and one borrow position, each in its own pool.
    function _loan(uint256 collateral, uint256 borrow) private view returns (ILendingCore.Loan memory loan) {
        loan.account = account;
        loan.collaterals = LoanHelpers.positions(collateralPool, collateral);
        loan.borrows = LoanHelpers.positions(borrowPool, borrow);
    }
}
