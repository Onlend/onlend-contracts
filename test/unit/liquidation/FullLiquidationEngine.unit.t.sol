// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {FullLiquidationEngine} from "src/liquidation/FullLiquidationEngine.sol";
import {ILiquidationEngine} from "src/liquidation/interfaces/ILiquidationEngine.sol";
import {ILoanEvaluator} from "src/loan/interfaces/ILoanEvaluator.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";

import {LoanHelpers} from "../../helpers/LoanHelpers.sol";

contract FullLiquidationEngineUnitTest is Test {
    uint256 constant FIRST_COLLATERAL = 100e18;
    uint256 constant SECOND_COLLATERAL = 30e18;
    uint256 constant FIRST_BORROW = 60e18;
    uint256 constant SECOND_BORROW = 20e18;

    // The engine ignores the loan's health and never calls the evaluator, so bare values suffice.
    uint256 constant HEALTH = 0.5e18;
    ILoanEvaluator constant EVALUATOR = ILoanEvaluator(address(0xE7A));

    address internal account;
    IPool internal firstCollateralPool;
    IPool internal secondCollateralPool;
    IPool internal firstBorrowPool;
    IPool internal secondBorrowPool;
    IPool internal unusedPool;

    FullLiquidationEngine internal implementation;
    FullLiquidationEngine internal engine;

    function setUp() public {
        account = makeAddr("account");
        firstCollateralPool = IPool(makeAddr("firstCollateralPool"));
        secondCollateralPool = IPool(makeAddr("secondCollateralPool"));
        firstBorrowPool = IPool(makeAddr("firstBorrowPool"));
        secondBorrowPool = IPool(makeAddr("secondBorrowPool"));
        unusedPool = IPool(makeAddr("unusedPool"));

        implementation = new FullLiquidationEngine();
        engine = FullLiquidationEngine(Clones.clone(address(implementation)));
        engine.initialize();
    }

    // liquidate()

    function test_liquidate_ReturnsEveryLoanPositionWhenRequestsMatchExactly() public view {
        ILendingCore.Loan memory loan = _loan();

        (ILendingCore.LoanPosition[] memory colsToSeize, ILendingCore.LoanPosition[] memory borsToRepay) =
            engine.liquidate(loan, HEALTH, _exactCollateralRequest(), _exactBorrowRequest(), EVALUATOR);

        _assertPositions(colsToSeize, loan.collaterals);
        _assertPositions(borsToRepay, loan.borrows);
    }

    function test_liquidate_ReturnsNoPositionsForEmptyLoan() public view {
        ILendingCore.LoanPosition[] memory empty = LoanHelpers.noPositions();

        (ILendingCore.LoanPosition[] memory colsToSeize, ILendingCore.LoanPosition[] memory borsToRepay) =
            engine.liquidate(LoanHelpers.emptyLoan(), HEALTH, empty, empty, EVALUATOR);

        assertEq(colsToSeize.length, 0);
        assertEq(borsToRepay.length, 0);
    }

    function test_liquidate_SeizesFullAmountWhenRequestedCollateralIsBelowLoanAmount() public view {
        ILendingCore.LoanPosition[] memory reqCols = _exactCollateralRequest();
        reqCols[0].amount = 40e18;

        (ILendingCore.LoanPosition[] memory colsToSeize,) =
            engine.liquidate(_loan(), HEALTH, reqCols, _exactBorrowRequest(), EVALUATOR);

        assertEq(colsToSeize[0].amount, FIRST_COLLATERAL);
    }

    function test_liquidate_SeizesFullAmountWhenRequestedCollateralEqualsLoanAmount() public view {
        ILendingCore.LoanPosition[] memory reqCols = _exactCollateralRequest();
        reqCols[0].amount = FIRST_COLLATERAL;

        (ILendingCore.LoanPosition[] memory colsToSeize,) =
            engine.liquidate(_loan(), HEALTH, reqCols, _exactBorrowRequest(), EVALUATOR);

        assertEq(colsToSeize[0].amount, FIRST_COLLATERAL);
    }

    function test_liquidate_RepaysFullAmountWhenRequestedBorrowIsAboveLoanAmount() public view {
        ILendingCore.LoanPosition[] memory reqBors = _exactBorrowRequest();
        reqBors[0].amount = 90e18;

        (, ILendingCore.LoanPosition[] memory borsToRepay) =
            engine.liquidate(_loan(), HEALTH, _exactCollateralRequest(), reqBors, EVALUATOR);

        assertEq(borsToRepay[0].amount, FIRST_BORROW);
    }

    function test_liquidate_RepaysFullAmountWhenRequestedBorrowEqualsLoanAmount() public view {
        ILendingCore.LoanPosition[] memory reqBors = _exactBorrowRequest();
        reqBors[0].amount = FIRST_BORROW;

        (, ILendingCore.LoanPosition[] memory borsToRepay) =
            engine.liquidate(_loan(), HEALTH, _exactCollateralRequest(), reqBors, EVALUATOR);

        assertEq(borsToRepay[0].amount, FIRST_BORROW);
    }

    /// @dev A violator front-running with a dust deposit into a pool the request does not name must not be able to
    ///      block the liquidation; the extra position is seized instead.
    function test_liquidate_SeizesCollateralOmittedFromRequest() public view {
        ILendingCore.Loan memory loan = _loan();
        ILendingCore.LoanPosition[] memory reqCols = LoanHelpers.positions(firstCollateralPool, FIRST_COLLATERAL);

        (ILendingCore.LoanPosition[] memory colsToSeize,) =
            engine.liquidate(loan, HEALTH, reqCols, _exactBorrowRequest(), EVALUATOR);

        _assertPositions(colsToSeize, loan.collaterals);
    }

    function test_liquidate_SeizesAllCollateralWhenNoneRequested() public view {
        ILendingCore.Loan memory loan = _loan();
        ILendingCore.LoanPosition[] memory reqCols = LoanHelpers.noPositions();

        (ILendingCore.LoanPosition[] memory colsToSeize,) =
            engine.liquidate(loan, HEALTH, reqCols, _exactBorrowRequest(), EVALUATOR);

        _assertPositions(colsToSeize, loan.collaterals);
    }

    function test_liquidate_AllowsZeroMinimumOnCollateralNotInLoan() public view {
        ILendingCore.Loan memory loan = _loan();
        ILendingCore.LoanPosition[] memory reqCols = LoanHelpers.positions(
            firstCollateralPool, FIRST_COLLATERAL, secondCollateralPool, SECOND_COLLATERAL, unusedPool, 0
        );

        (ILendingCore.LoanPosition[] memory colsToSeize,) =
            engine.liquidate(loan, HEALTH, reqCols, _exactBorrowRequest(), EVALUATOR);

        _assertPositions(colsToSeize, loan.collaterals);
    }

    /// @dev A borrow repaid by anyone between the request being built and the liquidation landing leaves the request
    ///      naming a pool the loan no longer holds; that must not block the liquidation either.
    function test_liquidate_IgnoresRequestedBorrowAbsentFromLoan() public view {
        ILendingCore.Loan memory loan = _loan();
        ILendingCore.LoanPosition[] memory reqBors =
            LoanHelpers.positions(firstBorrowPool, FIRST_BORROW, secondBorrowPool, SECOND_BORROW, unusedPool, 5e18);

        (, ILendingCore.LoanPosition[] memory borsToRepay) =
            engine.liquidate(loan, HEALTH, _exactCollateralRequest(), reqBors, EVALUATOR);

        _assertPositions(borsToRepay, loan.borrows);
    }

    function test_liquidate_RevertsWhenCollateralRequestedTwice() public {
        ILendingCore.LoanPosition[] memory reqCols =
            LoanHelpers.positions(firstCollateralPool, FIRST_COLLATERAL, firstCollateralPool, 1e18);

        vm.expectRevert(FullLiquidationEngine.DuplicateRequestedCollateral.selector);
        engine.liquidate(_loan(), HEALTH, reqCols, _exactBorrowRequest(), EVALUATOR);
    }

    function test_liquidate_RevertsWhenBorrowRequestedTwice() public {
        ILendingCore.LoanPosition[] memory reqBors = LoanHelpers.positions(
            firstBorrowPool, FIRST_BORROW, secondBorrowPool, SECOND_BORROW, firstBorrowPool, 1e18
        );

        vm.expectRevert(FullLiquidationEngine.DuplicateRequestedBorrow.selector);
        engine.liquidate(_loan(), HEALTH, _exactCollateralRequest(), reqBors, EVALUATOR);
    }

    /// @dev The repeated pool is absent from the loan, so walking the loan's borrows never reaches the second entry.
    ///      Only a direct scan of the request catches it.
    function test_liquidate_RevertsWhenBorrowRequestedTwiceAndAbsentFromLoan() public {
        ILendingCore.LoanPosition[] memory reqBors = new ILendingCore.LoanPosition[](4);
        reqBors[0] = ILendingCore.LoanPosition({pool: firstBorrowPool, amount: FIRST_BORROW});
        reqBors[1] = ILendingCore.LoanPosition({pool: secondBorrowPool, amount: SECOND_BORROW});
        reqBors[2] = ILendingCore.LoanPosition({pool: unusedPool, amount: 5e18});
        reqBors[3] = ILendingCore.LoanPosition({pool: unusedPool, amount: 7e18});

        vm.expectRevert(FullLiquidationEngine.DuplicateRequestedBorrow.selector);
        engine.liquidate(_loan(), HEALTH, _exactCollateralRequest(), reqBors, EVALUATOR);
    }

    function test_liquidate_RevertsWhenRequestedCollateralNotInLoanAndMinimumIsOne() public {
        ILendingCore.LoanPosition[] memory reqCols = LoanHelpers.positions(
            firstCollateralPool, FIRST_COLLATERAL, secondCollateralPool, SECOND_COLLATERAL, unusedPool, 1
        );

        vm.expectRevert(abi.encodeWithSelector(FullLiquidationEngine.InsufficientCollateral.selector, unusedPool, 1, 0));
        engine.liquidate(_loan(), HEALTH, reqCols, _exactBorrowRequest(), EVALUATOR);
    }

    function test_liquidate_RevertsWhenCollateralIsBelowRequestedMinimum() public {
        ILendingCore.LoanPosition[] memory reqCols = _exactCollateralRequest();
        reqCols[0].amount = FIRST_COLLATERAL + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                FullLiquidationEngine.InsufficientCollateral.selector,
                firstCollateralPool,
                FIRST_COLLATERAL + 1,
                FIRST_COLLATERAL
            )
        );
        engine.liquidate(_loan(), HEALTH, reqCols, _exactBorrowRequest(), EVALUATOR);
    }

    function test_liquidate_RevertsWhenLoanBorrowNotRequested() public {
        ILendingCore.LoanPosition[] memory reqBors = LoanHelpers.positions(firstBorrowPool, FIRST_BORROW);

        vm.expectRevert(abi.encodeWithSelector(FullLiquidationEngine.BorrowNotRequested.selector, secondBorrowPool));
        engine.liquidate(_loan(), HEALTH, _exactCollateralRequest(), reqBors, EVALUATOR);
    }

    function test_liquidate_RevertsWhenBorrowIsAboveRequestedMaximum() public {
        ILendingCore.LoanPosition[] memory reqBors = _exactBorrowRequest();
        reqBors[0].amount = FIRST_BORROW - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                FullLiquidationEngine.ExcessiveRepayment.selector, firstBorrowPool, FIRST_BORROW - 1, FIRST_BORROW
            )
        );
        engine.liquidate(_loan(), HEALTH, _exactCollateralRequest(), reqBors, EVALUATOR);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(engine.contractName(), "FullLiquidationEngine");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(engine.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_LiquidationEngine_ReturnsTrue() public view {
        assertTrue(engine.supportsInterface(type(ILiquidationEngine).interfaceId));
    }

    function test_supportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(engine.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(engine.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(engine.supportsInterface(0xffffffff));
        assertFalse(engine.supportsInterface(0xdeadbeef));
    }

    /// @dev A loan holding two collateral positions and two borrow positions, each in its own pool.
    function _loan() private view returns (ILendingCore.Loan memory loan) {
        loan.account = account;
        loan.collaterals =
            LoanHelpers.positions(firstCollateralPool, FIRST_COLLATERAL, secondCollateralPool, SECOND_COLLATERAL);
        loan.borrows = LoanHelpers.positions(firstBorrowPool, FIRST_BORROW, secondBorrowPool, SECOND_BORROW);
    }

    /// @dev Names both of the loan's collaterals at exactly the amounts it holds.
    function _exactCollateralRequest() private view returns (ILendingCore.LoanPosition[] memory reqCols) {
        return LoanHelpers.positions(firstCollateralPool, FIRST_COLLATERAL, secondCollateralPool, SECOND_COLLATERAL);
    }

    /// @dev Names both of the loan's borrows at exactly the amounts it owes.
    function _exactBorrowRequest() private view returns (ILendingCore.LoanPosition[] memory reqBors) {
        return LoanHelpers.positions(firstBorrowPool, FIRST_BORROW, secondBorrowPool, SECOND_BORROW);
    }

    function _assertPositions(ILendingCore.LoanPosition[] memory actual, ILendingCore.LoanPosition[] memory expected)
        private
        pure
    {
        assertEq(actual.length, expected.length);
        for (uint256 i; i < expected.length; ++i) {
            assertEq(address(actual[i].pool), address(expected[i].pool));
            assertEq(actual[i].amount, expected[i].amount);
        }
    }
}
