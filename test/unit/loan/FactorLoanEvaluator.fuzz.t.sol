// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {FactorLoanEvaluator} from "src/loan/FactorLoanEvaluator.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {LoanHelpers} from "../../helpers/LoanHelpers.sol";
import {MockOracle} from "../../mocks/MockOracle.sol";

contract FactorLoanEvaluatorFuzzTest is Test {
    uint16 internal constant COLLATERAL_FACTOR = 8000;
    uint32 internal constant BORROW_FACTOR = 11_000;

    /// @dev A factor of exactly one, i.e. a pool whose collateral is not discounted and whose borrows are not
    ///      inflated.
    uint16 internal constant UNIT_FACTOR = 10_000;

    uint256 internal constant MIN_HEALTH_FACTOR = 1.1e18;

    /// @dev The two pools are priced differently and hold assets of different decimals, so no valuation can pass by
    ///      ignoring the oracle. Amounts stay well below the point where a health would overflow.
    uint256 internal constant COLLATERAL_POOL_PRICE = 2e18;
    uint8 internal constant COLLATERAL_POOL_DECIMALS = 18;
    uint256 internal constant BORROW_POOL_PRICE = 3e18;
    uint8 internal constant BORROW_POOL_DECIMALS = 6;
    uint256 internal constant MAX_AMOUNT = 1e27;

    address internal borrower;
    address internal factorConfigurator;
    MockOracle internal oracle;
    IPool internal collateralPool;
    IPool internal borrowPool;

    FactorLoanEvaluator internal implementation;
    FactorLoanEvaluator internal evaluator;

    function setUp() public {
        borrower = makeAddr("borrower");
        factorConfigurator = makeAddr("factorConfigurator");
        collateralPool = IPool(makeAddr("collateralPool"));
        borrowPool = IPool(makeAddr("borrowPool"));

        oracle = new MockOracle();
        oracle.setPrice(collateralPool, COLLATERAL_POOL_PRICE, COLLATERAL_POOL_DECIMALS);
        oracle.setPrice(borrowPool, BORROW_POOL_PRICE, BORROW_POOL_DECIMALS);

        implementation = new FactorLoanEvaluator();
        evaluator = _deploy(COLLATERAL_FACTOR, BORROW_FACTOR, MIN_HEALTH_FACTOR);
    }

    // isLoanHealthy()

    function testFuzz_isLoanHealthy_ReturnsTrueWhenCollateralIsAtLeastBorrow(uint256 collateral, uint256 borrow)
        public
    {
        borrow = bound(borrow, 0, MAX_AMOUNT);
        collateral = bound(collateral, borrow, MAX_AMOUNT);
        FactorLoanEvaluator instance = _unitEvaluator();

        bool healthy = instance.isLoanHealthy(_singlePoolLoan(collateral, borrow));

        assertTrue(healthy);
    }

    function testFuzz_isLoanHealthy_ReturnsFalseWhenCollateralIsBelowBorrow(uint256 collateral, uint256 borrow) public {
        borrow = bound(borrow, 1, MAX_AMOUNT);
        collateral = bound(collateral, 0, borrow - 1);
        FactorLoanEvaluator instance = _unitEvaluator();

        bool healthy = instance.isLoanHealthy(_singlePoolLoan(collateral, borrow));

        assertFalse(healthy);
    }

    function testFuzz_isLoanHealthy_NeverHoldsForALiquidatableLoan(uint256 collateral, uint256 borrow) public view {
        collateral = bound(collateral, 0, MAX_AMOUNT);
        borrow = bound(borrow, 0, MAX_AMOUNT);
        ILendingCore.Loan memory loan = _loan(collateral, borrow);

        (bool liquidatable,) = evaluator.isLoanLiquidatable(loan);

        if (evaluator.isLoanHealthy(loan)) assertFalse(liquidatable);
    }

    // isLoanLiquidatable()

    function testFuzz_isLoanLiquidatable_ReturnsTrueWhenCollateralIsBelowBorrow(uint256 collateral, uint256 borrow)
        public
    {
        borrow = bound(borrow, 1, MAX_AMOUNT);
        collateral = bound(collateral, 0, borrow - 1);
        FactorLoanEvaluator instance = _unitEvaluator();

        (bool liquidatable,) = instance.isLoanLiquidatable(_singlePoolLoan(collateral, borrow));

        assertTrue(liquidatable);
    }

    function testFuzz_isLoanLiquidatable_ReturnsFalseWhenCollateralIsAtLeastBorrow(uint256 collateral, uint256 borrow)
        public
    {
        borrow = bound(borrow, 0, MAX_AMOUNT);
        collateral = bound(collateral, borrow, MAX_AMOUNT);
        FactorLoanEvaluator instance = _unitEvaluator();

        (bool liquidatable,) = instance.isLoanLiquidatable(_singlePoolLoan(collateral, borrow));

        assertFalse(liquidatable);
    }

    function testFuzz_isLoanLiquidatable_PlacesTheBoundaryAtOne(uint256 collateral, uint256 borrow) public view {
        collateral = bound(collateral, 0, MAX_AMOUNT);
        borrow = bound(borrow, 0, MAX_AMOUNT);
        ILendingCore.Loan memory loan = _loan(collateral, borrow);

        (bool liquidatable, uint256 health) = evaluator.isLoanLiquidatable(loan);

        assertEq(liquidatable, health < 1e18);
    }

    function testFuzz_isLoanLiquidatable_ReportsTheSameHealthAsGetLoanHealth(uint256 collateral, uint256 borrow)
        public
        view
    {
        collateral = bound(collateral, 0, MAX_AMOUNT);
        borrow = bound(borrow, 0, MAX_AMOUNT);
        ILendingCore.Loan memory loan = _loan(collateral, borrow);

        (, uint256 health) = evaluator.isLoanLiquidatable(loan);

        assertEq(health, evaluator.getLoanHealth(loan));
    }

    // getLoanHealth()

    function testFuzz_getLoanHealth_ReturnsMaxWhenLoanHasNoBorrows(uint256 collateral) public view {
        collateral = bound(collateral, 0, MAX_AMOUNT);

        uint256 health =
            evaluator.getLoanHealth(LoanHelpers.loanWithSingleCollateral(borrower, collateralPool, collateral));

        assertEq(health, type(uint256).max);
    }

    function testFuzz_getLoanHealth_NeverFallsWhenCollateralRises(uint256 lesser, uint256 greater, uint256 borrow)
        public
        view
    {
        lesser = bound(lesser, 0, MAX_AMOUNT);
        greater = bound(greater, lesser, MAX_AMOUNT);
        borrow = bound(borrow, 1, MAX_AMOUNT);

        uint256 lesserHealth = evaluator.getLoanHealth(_loan(lesser, borrow));
        uint256 greaterHealth = evaluator.getLoanHealth(_loan(greater, borrow));

        assertLe(lesserHealth, greaterHealth);
    }

    function testFuzz_getLoanHealth_NeverRisesWhenBorrowRises(uint256 collateral, uint256 lesser, uint256 greater)
        public
        view
    {
        collateral = bound(collateral, 0, MAX_AMOUNT);
        lesser = bound(lesser, 1, MAX_AMOUNT);
        greater = bound(greater, lesser, MAX_AMOUNT);

        uint256 lesserHealth = evaluator.getLoanHealth(_loan(collateral, lesser));
        uint256 greaterHealth = evaluator.getLoanHealth(_loan(collateral, greater));

        assertGe(lesserHealth, greaterHealth);
    }

    function testFuzz_getLoanHealth_NeverFallsWhenCollateralFactorRises(
        uint16 lesserFactor,
        uint16 greaterFactor,
        uint256 collateral,
        uint256 borrow
    ) public {
        lesserFactor = uint16(bound(lesserFactor, 0, UNIT_FACTOR));
        greaterFactor = uint16(bound(greaterFactor, lesserFactor, UNIT_FACTOR));
        collateral = bound(collateral, 0, MAX_AMOUNT);
        borrow = bound(borrow, 1, MAX_AMOUNT);
        FactorLoanEvaluator instance = _deploy(lesserFactor, BORROW_FACTOR, MIN_HEALTH_FACTOR);
        uint256 lesserHealth = instance.getLoanHealth(_loan(collateral, borrow));

        vm.prank(factorConfigurator);
        instance.updateCollateralFactor(collateralPool, greaterFactor);

        assertLe(lesserHealth, instance.getLoanHealth(_loan(collateral, borrow)));
    }

    function testFuzz_getLoanHealth_NeverRisesWhenBorrowFactorRises(
        uint32 lesserFactor,
        uint32 greaterFactor,
        uint256 collateral,
        uint256 borrow
    ) public {
        lesserFactor = uint32(bound(lesserFactor, UNIT_FACTOR, type(uint32).max));
        greaterFactor = uint32(bound(greaterFactor, lesserFactor, type(uint32).max));
        collateral = bound(collateral, 0, MAX_AMOUNT);
        borrow = bound(borrow, 1, MAX_AMOUNT);
        FactorLoanEvaluator instance = _deploy(COLLATERAL_FACTOR, lesserFactor, MIN_HEALTH_FACTOR);
        uint256 lesserHealth = instance.getLoanHealth(_loan(collateral, borrow));

        vm.prank(factorConfigurator);
        instance.updateBorrowFactor(borrowPool, greaterFactor);

        assertGe(lesserHealth, instance.getLoanHealth(_loan(collateral, borrow)));
    }

    function testFuzz_getLoanHealth_ReturnsZeroWhenCollateralIsFullyDiscounted(uint256 collateral, uint256 borrow)
        public
    {
        collateral = bound(collateral, 0, MAX_AMOUNT);
        borrow = bound(borrow, 1, MAX_AMOUNT);
        FactorLoanEvaluator instance = _deploy(0, BORROW_FACTOR, MIN_HEALTH_FACTOR);

        uint256 health = instance.getLoanHealth(_loan(collateral, borrow));

        assertEq(health, 0);
    }

    // Helpers

    function _deploy(uint16 collateralFactor, uint32 borrowFactor, uint256 minHealthFactor)
        internal
        returns (FactorLoanEvaluator instance)
    {
        FactorLoanEvaluator.PoolFactorConfig[] memory configs = new FactorLoanEvaluator.PoolFactorConfig[](2);
        configs[0] = FactorLoanEvaluator.PoolFactorConfig({
            pool: collateralPool, collateralFactor: collateralFactor, borrowFactor: borrowFactor
        });
        configs[1] = FactorLoanEvaluator.PoolFactorConfig({
            pool: borrowPool, collateralFactor: collateralFactor, borrowFactor: borrowFactor
        });

        instance = FactorLoanEvaluator(Clones.clone(address(implementation)));
        instance.initialize(address(0), address(0), factorConfigurator, address(oracle), minHealthFactor, configs);
    }

    /// @dev An evaluator that neither discounts collateral nor inflates borrows, and demands no margin above
    ///      solvency. Against it, a loan holding one pool on both sides is healthy exactly while its collateral
    ///      amount is at least its borrow amount: the pool's price scales both sides alike and so cancels.
    function _unitEvaluator() internal returns (FactorLoanEvaluator) {
        return _deploy(UNIT_FACTOR, UNIT_FACTOR, 1e18);
    }

    /// @dev A loan holding one collateral position and one borrow position, each in its own pool.
    function _loan(uint256 collateral, uint256 borrow) private view returns (ILendingCore.Loan memory loan) {
        loan.account = borrower;
        loan.collaterals = LoanHelpers.positions(collateralPool, collateral);
        loan.borrows = LoanHelpers.positions(borrowPool, borrow);
    }

    /// @dev A loan whose collateral and borrow are both held in `collateralPool`.
    function _singlePoolLoan(uint256 collateral, uint256 borrow) private view returns (ILendingCore.Loan memory loan) {
        loan.account = borrower;
        loan.collaterals = LoanHelpers.positions(collateralPool, collateral);
        loan.borrows = LoanHelpers.positions(collateralPool, borrow);
    }
}
