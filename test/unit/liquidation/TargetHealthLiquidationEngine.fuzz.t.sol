// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {TargetHealthLiquidationEngine} from "src/liquidation/TargetHealthLiquidationEngine.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockLoanEvaluator} from "../loan/mocks/MockLoanEvaluator.sol";
import {MockOracle} from "../../mocks/MockOracle.sol";
import {LoanHelpers} from "../../helpers/LoanHelpers.sol";

contract TargetHealthLiquidationEngineFuzzTest is Test {
    /// @dev Both pools are priced at one unit of numeraire per token unit, so a position's value is its amount.
    uint256 constant UNIT_PRICE = 1;
    uint8 constant UNIT_PRICE_DECIMALS = 0;

    uint256 constant TARGET_HEALTH_FACTOR = 1.05e18;
    uint256 constant RAMP_START_HEALTH = 1e18;
    uint256 constant RAMP_END_HEALTH = 0.9e18;

    /// @dev The collateral pays nothing at the ramp's start and 20% at its end, so above the start a seizure
    ///      costs exactly its own value and no arithmetic is needed to predict it.
    uint16 constant MIN_BONUS = 0;
    uint16 constant MAX_BONUS = 2000;

    uint256 constant COLLATERAL = 1000e18;
    uint256 constant BORROW = 1000e18;

    uint256 constant MIN_LEFTOVER_VALUE = 100e18;
    /// @dev The most that can be repaid while still leaving the threshold behind.
    uint256 constant DUST_FREE_REPAYMENT = BORROW - MIN_LEFTOVER_VALUE;
    /// @dev Below `BORROW`, so repaying all of it is a close-out above the cap.
    uint256 constant CLOSE_OUT_THRESHOLD = 2 * MIN_LEFTOVER_VALUE;
    /// @dev Exactly the close-out threshold, for tests that repay the whole debt and expect it to be accepted.
    uint256 constant CLOSABLE_BORROW = CLOSE_OUT_THRESHOLD;

    address internal liquidationConfigurator;
    address internal violator;

    MockOracle internal oracle;
    MockLoanEvaluator internal evaluator;
    IPool internal collateralPool;
    IPool internal borrowPool;

    TargetHealthLiquidationEngine internal implementation;
    TargetHealthLiquidationEngine internal engine;

    function setUp() public {
        liquidationConfigurator = makeAddr("liquidationConfigurator");
        violator = makeAddr("violator");

        collateralPool = IPool(makeAddr("collateralPool"));
        borrowPool = IPool(makeAddr("borrowPool"));

        evaluator = new MockLoanEvaluator();
        evaluator.setHealth(1e18);

        oracle = new MockOracle();
        oracle.setPrice(collateralPool, UNIT_PRICE, UNIT_PRICE_DECIMALS);
        oracle.setPrice(borrowPool, UNIT_PRICE, UNIT_PRICE_DECIMALS);

        TargetHealthLiquidationEngine.CollateralBonusConfig[] memory configs =
            new TargetHealthLiquidationEngine.CollateralBonusConfig[](1);
        configs[0] = TargetHealthLiquidationEngine.CollateralBonusConfig({
            pool: collateralPool, minBonus: MIN_BONUS, maxBonus: MAX_BONUS
        });

        implementation = new TargetHealthLiquidationEngine();
        engine = TargetHealthLiquidationEngine(Clones.clone(address(implementation)));
        engine.initialize(
            address(0),
            address(0),
            liquidationConfigurator,
            address(oracle),
            TARGET_HEALTH_FACTOR,
            RAMP_START_HEALTH,
            RAMP_END_HEALTH,
            0,
            CLOSE_OUT_THRESHOLD,
            configs
        );
    }

    // updateBonusRamp()

    function testFuzz_updateBonusRamp_RevertsWhenStartIsAtOrBelowEnd(uint256 startHealth, uint256 endHealth) public {
        startHealth = bound(startHealth, 0, endHealth);

        vm.expectRevert(
            abi.encodeWithSelector(TargetHealthLiquidationEngine.BonusRampInvalid.selector, startHealth, endHealth)
        );
        vm.prank(liquidationConfigurator);
        engine.updateBonusRamp(startHealth, endHealth);
    }

    function testFuzz_updateBonusRamp_RevertsWhenStartIsAboveOne(uint256 startHealth, uint256 endHealth) public {
        startHealth = bound(startHealth, 1e18 + 1, type(uint256).max);
        endHealth = bound(endHealth, 0, 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(TargetHealthLiquidationEngine.BonusRampStartTooHigh.selector, startHealth)
        );
        vm.prank(liquidationConfigurator);
        engine.updateBonusRamp(startHealth, endHealth);
    }

    // updateMinLeftoverValue()

    function testFuzz_updateMinLeftoverValue_RevertsWhenAtOrAboveCloseOutThreshold(uint256 minLeftoverValue) public {
        minLeftoverValue = bound(minLeftoverValue, CLOSE_OUT_THRESHOLD, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.CloseOutWindowEmpty.selector, minLeftoverValue, CLOSE_OUT_THRESHOLD
            )
        );
        vm.prank(liquidationConfigurator);
        engine.updateMinLeftoverValue(minLeftoverValue);
    }

    // updateCloseOutThreshold()

    function testFuzz_updateCloseOutThreshold_RevertsWhenAtOrBelowMinLeftoverValue(uint256 closeOutThreshold) public {
        _setMinLeftoverValue();
        closeOutThreshold = bound(closeOutThreshold, 0, MIN_LEFTOVER_VALUE);

        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.CloseOutWindowEmpty.selector, MIN_LEFTOVER_VALUE, closeOutThreshold
            )
        );
        vm.prank(liquidationConfigurator);
        engine.updateCloseOutThreshold(closeOutThreshold);
    }

    // liquidate()

    function testFuzz_liquidate_SeizesExactlyTheRequestedCollateral(uint256 seizeAmount) public view {
        seizeAmount = bound(seizeAmount, 1, CLOSABLE_BORROW);

        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            _loan(COLLATERAL, CLOSABLE_BORROW),
            RAMP_END_HEALTH,
            LoanHelpers.positions(collateralPool, seizeAmount),
            LoanHelpers.positions(borrowPool, seizeAmount),
            evaluator
        );

        assertEq(colsToSeize[0].amount, seizeAmount);
    }

    function testFuzz_liquidate_ResolvesMaxToWholeCollateralPosition(uint256 collateral) public view {
        collateral = bound(collateral, 1, CLOSABLE_BORROW);

        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            _loan(collateral, CLOSABLE_BORROW),
            RAMP_END_HEALTH,
            LoanHelpers.positions(collateralPool, type(uint256).max),
            LoanHelpers.positions(borrowPool, collateral),
            evaluator
        );

        assertEq(colsToSeize[0].amount, collateral);
    }

    function testFuzz_liquidate_RepaysTheRequestWhenItIsBelowTheDebtOwed(uint256 repayAmount) public view {
        repayAmount = bound(repayAmount, 1, BORROW - 1);

        (, ILendingCore.LoanPosition[] memory borsToRepay) = _liquidate(RAMP_START_HEALTH, 0, repayAmount);

        assertEq(borsToRepay[0].amount, repayAmount);
    }

    function testFuzz_liquidate_RepaysTheDebtOwedWhenTheRequestIsAbove(uint256 repayAmount) public view {
        repayAmount = bound(repayAmount, CLOSABLE_BORROW, type(uint256).max);

        (, ILendingCore.LoanPosition[] memory borsToRepay) = engine.liquidate(
            _loan(COLLATERAL, CLOSABLE_BORROW),
            RAMP_START_HEALTH,
            LoanHelpers.positions(collateralPool, 0),
            LoanHelpers.positions(borrowPool, repayAmount),
            evaluator
        );

        assertEq(borsToRepay[0].amount, CLOSABLE_BORROW);
    }

    /// @dev Above the ramp's start the collateral pays no bonus, so a repayment buys exactly its own value of
    ///      collateral, with no rounding either way.
    function testFuzz_liquidate_ChargesNoBonusAboveTheRampStart(uint256 health, uint256 amount) public view {
        health = bound(health, RAMP_START_HEALTH, type(uint256).max);
        amount = bound(amount, 1, COLLATERAL - 1);

        (ILendingCore.LoanPosition[] memory colsToSeize,) = _liquidate(health, amount, amount);

        assertEq(colsToSeize[0].amount, amount);
    }

    function testFuzz_liquidate_RevertsWhenSeizingOneMoreThanTheRepaymentBuysAboveTheRampStart(
        uint256 health,
        uint256 amount
    ) public {
        health = bound(health, RAMP_START_HEALTH, type(uint256).max);
        amount = bound(amount, 1, COLLATERAL - 1);

        vm.expectRevert(
            abi.encodeWithSelector(TargetHealthLiquidationEngine.InsufficientRepayment.selector, amount, amount + 1)
        );
        _liquidate(health, amount + 1, amount);
    }

    /// @dev The bonus only ever grows as health falls, so a liquidation the engine accepts at one health must
    ///      still be accepted at any lower one. The seizure is drawn from the window where acceptance turns on
    ///      the bonus, which is up to a fifth above the repayment.
    function testFuzz_liquidate_NeverRejectsAtALowerHealthWhatItAcceptedAtAHigherOne(
        uint256 higherHealth,
        uint256 lowerHealth,
        uint256 repayAmount,
        uint256 seizeAmount
    ) public view {
        higherHealth = bound(higherHealth, RAMP_END_HEALTH, RAMP_START_HEALTH);
        lowerHealth = bound(lowerHealth, 0, higherHealth);
        repayAmount = bound(repayAmount, 1, (COLLATERAL * 5) / 6);
        seizeAmount = bound(seizeAmount, repayAmount, repayAmount + repayAmount / 5);

        bool acceptedAtHigherHealth = _accepts(BORROW, higherHealth, seizeAmount, repayAmount);
        bool acceptedAtLowerHealth = _accepts(BORROW, lowerHealth, seizeAmount, repayAmount);

        assertTrue(!acceptedAtHigherHealth || acceptedAtLowerHealth);
    }

    /// @dev Repaying more can only buy more collateral, so it can never turn an accepted liquidation away. The
    ///      evaluator reports a fixed health here, which leaves the entitlement as the only check in play.
    function testFuzz_liquidate_NeverRejectsALargerRepaymentItAcceptedASmallerOneFor(
        uint256 smallerRepayAmount,
        uint256 largerRepayAmount,
        uint256 seizeAmount
    ) public view {
        smallerRepayAmount = bound(smallerRepayAmount, 1, CLOSABLE_BORROW);
        largerRepayAmount = bound(largerRepayAmount, smallerRepayAmount, CLOSABLE_BORROW);
        seizeAmount = bound(seizeAmount, 1, CLOSABLE_BORROW);

        bool acceptedAtSmallerRepayment = _accepts(CLOSABLE_BORROW, RAMP_END_HEALTH, seizeAmount, smallerRepayAmount);
        bool acceptedAtLargerRepayment = _accepts(CLOSABLE_BORROW, RAMP_END_HEALTH, seizeAmount, largerRepayAmount);

        assertTrue(!acceptedAtSmallerRepayment || acceptedAtLargerRepayment);
    }

    function testFuzz_liquidate_RevertsWhenCollateralIsNotInLoanAndAmountIsNeitherZeroNorMax(uint256 seizeAmount)
        public
    {
        IPool unheldPool = IPool(makeAddr("unheldPool"));
        seizeAmount = bound(seizeAmount, 1, type(uint256).max - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.InsufficientCollateral.selector, unheldPool, seizeAmount, 0
            )
        );
        engine.liquidate(
            _loan(COLLATERAL, BORROW),
            RAMP_END_HEALTH,
            LoanHelpers.positions(unheldPool, seizeAmount),
            LoanHelpers.positions(borrowPool, BORROW),
            evaluator
        );
    }

    function testFuzz_liquidate_RevertsWhenTheCollateralExceedsTheLoanPosition(uint256 seizeAmount) public {
        seizeAmount = bound(seizeAmount, COLLATERAL + 1, type(uint256).max - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.InsufficientCollateral.selector, collateralPool, seizeAmount, COLLATERAL
            )
        );
        _liquidate(RAMP_END_HEALTH, seizeAmount, BORROW);
    }

    /// @dev Above the ramp's start the collateral pays no bonus, so seizing the debt's own value is exactly paid for.
    function testFuzz_liquidate_AcceptsCloseOutAtOrBelowTheThreshold(uint256 borrow) public view {
        borrow = bound(borrow, 1, CLOSE_OUT_THRESHOLD);

        (, ILendingCore.LoanPosition[] memory borsToRepay) = engine.liquidate(
            _loan(COLLATERAL, borrow),
            RAMP_START_HEALTH,
            LoanHelpers.positions(collateralPool, borrow),
            LoanHelpers.positions(borrowPool, borrow),
            evaluator
        );

        assertEq(borsToRepay[0].amount, borrow);
    }

    function testFuzz_liquidate_RevertsWhenCloseOutIsAboveTheThreshold(uint256 borrow) public {
        borrow = bound(borrow, CLOSE_OUT_THRESHOLD + 1, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(TargetHealthLiquidationEngine.CloseOutTooLarge.selector, borrow, CLOSE_OUT_THRESHOLD)
        );
        engine.liquidate(
            _loan(COLLATERAL, borrow),
            RAMP_START_HEALTH,
            LoanHelpers.positions(collateralPool, 0),
            LoanHelpers.positions(borrowPool, borrow),
            evaluator
        );
    }

    function testFuzz_liquidate_AcceptsHealthAfterAtOrBelowTheTarget(uint256 healthAfter) public {
        healthAfter = bound(healthAfter, 0, TARGET_HEALTH_FACTOR);
        evaluator.setHealth(healthAfter);

        (ILendingCore.LoanPosition[] memory colsToSeize,) = _liquidate(RAMP_START_HEALTH, 10e18, 10e18);

        assertEq(colsToSeize[0].amount, 10e18);
    }

    function testFuzz_liquidate_RevertsWhenHealthAfterIsAboveTheTarget(uint256 healthAfter) public {
        healthAfter = bound(healthAfter, TARGET_HEALTH_FACTOR + 1, type(uint256).max);
        evaluator.setHealth(healthAfter);

        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.TargetHealthExceeded.selector, healthAfter, TARGET_HEALTH_FACTOR
            )
        );
        _liquidate(RAMP_START_HEALTH, 10e18, 10e18);
    }

    function testFuzz_liquidate_AcceptsLeftoversAtOrAboveMinLeftoverValue(uint256 repayAmount) public {
        _setMinLeftoverValue();
        repayAmount = bound(repayAmount, 1, DUST_FREE_REPAYMENT);

        (, ILendingCore.LoanPosition[] memory borsToRepay) = _liquidate(RAMP_START_HEALTH, 0, repayAmount);

        assertEq(borsToRepay[0].amount, repayAmount);
    }

    function testFuzz_liquidate_RevertsWhenLeftoverBorrowsAreBelowMinLeftoverValue(uint256 repayAmount) public {
        _setMinLeftoverValue();
        repayAmount = bound(repayAmount, DUST_FREE_REPAYMENT + 1, BORROW - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.MustNotLeaveDust.selector, COLLATERAL, BORROW - repayAmount
            )
        );
        _liquidate(RAMP_START_HEALTH, 0, repayAmount);
    }

    // Helpers

    function _setMinLeftoverValue() internal {
        vm.prank(liquidationConfigurator);
        engine.updateMinLeftoverValue(MIN_LEFTOVER_VALUE);
    }

    function _loan(uint256 collateral, uint256 borrow) internal view returns (ILendingCore.Loan memory loan) {
        loan.account = violator;
        loan.collaterals = LoanHelpers.positions(collateralPool, collateral);
        loan.borrows = LoanHelpers.positions(borrowPool, borrow);
    }

    function _liquidate(uint256 health, uint256 seizeAmount, uint256 repayAmount)
        internal
        view
        returns (ILendingCore.LoanPosition[] memory colsToSeize, ILendingCore.LoanPosition[] memory borsToRepay)
    {
        return engine.liquidate(
            _loan(COLLATERAL, BORROW),
            health,
            LoanHelpers.positions(collateralPool, seizeAmount),
            LoanHelpers.positions(borrowPool, repayAmount),
            evaluator
        );
    }

    function _accepts(uint256 borrow, uint256 health, uint256 seizeAmount, uint256 repayAmount)
        internal
        view
        returns (bool)
    {
        try engine.liquidate(
            _loan(COLLATERAL, borrow),
            health,
            LoanHelpers.positions(collateralPool, seizeAmount),
            LoanHelpers.positions(borrowPool, repayAmount),
            evaluator
        ) returns (
            ILendingCore.LoanPosition[] memory, ILendingCore.LoanPosition[] memory
        ) {
            return true;
        } catch {
            return false;
        }
    }
}
