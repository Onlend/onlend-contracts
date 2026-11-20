// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {InterestMath} from "src/pool/lib/InterestMath.sol";
import {InterestMathHarness} from "./mocks/InterestMathHarness.sol";

contract InterestMathUnitTest is Test {
    uint256 constant AMOUNT = 1000e18;
    uint256 constant BORROW_RATE = 0.1e18;
    uint256 constant RETENTION_RATE = 0.2e18;
    uint256 constant FIXED_FEE_BPS = 1000;
    uint256 constant SPLIT_FEE_BPS = 2500;
    // Borrow rate whose truncated per-second rate is exactly 1%, so a single second compounds by exactly 1.01.
    uint256 constant ONE_PERCENT_PER_SECOND_BORROW_RATE = 0.01e18 * 365 days;

    InterestMathHarness internal harness;

    function setUp() public {
        harness = new InterestMathHarness();
    }

    // calcUtilisation()

    function test_calcUtilisation_ReturnsZeroWhenThereIsNoLiquidity() public pure {
        assertEq(InterestMath.calcUtilisation(0, 0), 0);
    }

    function test_calcUtilisation_ReturnsZeroWhenThereIsNoDebt() public pure {
        assertEq(InterestMath.calcUtilisation(100e18, 0), 0);
    }

    function test_calcUtilisation_ReturnsOneWhenThereIsNoIdleLiquidity() public pure {
        assertEq(InterestMath.calcUtilisation(0, 100e18), 1e18);
    }

    function test_calcUtilisation_ReturnsBorrowedShare() public pure {
        assertEq(InterestMath.calcUtilisation(25e18, 75e18), 0.75e18);
    }

    function test_calcUtilisation_RoundsDown() public pure {
        assertEq(InterestMath.calcUtilisation(2, 1), 333_333_333_333_333_333);
    }

    function test_calcUtilisation_RevertsWhenTotalLiquidityOverflows() public {
        vm.expectRevert(stdError.arithmeticError);
        harness.calcUtilisation(type(uint256).max, 1);
    }

    // calcBorrowIndex()

    function test_calcBorrowIndex_ReturnsPreviousBorrowIndexWhenBorrowRateIsZero() public pure {
        assertEq(InterestMath.calcBorrowIndex(MathUtils.ONE_18_DP, 0, 365 days), MathUtils.ONE_18_DP);
    }

    function test_calcBorrowIndex_ReturnsPreviousBorrowIndexWhenElapsedIsZero() public pure {
        assertEq(InterestMath.calcBorrowIndex(MathUtils.ONE_18_DP, BORROW_RATE, 0), MathUtils.ONE_18_DP);
    }

    /// @dev An annual rate below one unit per second truncates to a zero per-second rate, so it cannot accrue at all.
    function test_calcBorrowIndex_DoesNotAccrueWhenBorrowRateTruncatesToZeroPerSecond() public pure {
        assertEq(
            InterestMath.calcBorrowIndex(MathUtils.ONE_18_DP, MathUtils.SECONDS_IN_YEAR - 1, 365 days),
            MathUtils.ONE_18_DP
        );
    }

    /// @dev A 100% annual rate is a per-second rate of `1 / 365 days`, i.e. 0.0000000031709791983 per second.
    function test_calcBorrowIndex_AccruesOneSecondBorrowIndex() public pure {
        assertEq(InterestMath.calcBorrowIndex(MathUtils.ONE_18_DP, MathUtils.ONE_18_DP, 1), 1.000000031709791983e18);
    }

    /// @dev A 10% annual rate compounded every second over a year is `e ** 0.1 = 1.10517091808...`, above the 1.1
    ///      simple-interest result. The index lands a shade under the continuous value because the per-second rate is
    ///      truncated and every squaring floors.
    function test_calcBorrowIndex_CompoundsOverAYear() public pure {
        assertEq(InterestMath.calcBorrowIndex(MathUtils.ONE_18_DP, 0.1e18, 365 days), 1.105170917878694255e18);
    }

    /// @dev The period's growth is applied to the index it starts from rather than restated from par, so an index that
    ///      has already doubled takes the same 1% as a par one does.
    function test_calcBorrowIndex_CompoundsFromAccruedBorrowIndex() public pure {
        assertEq(InterestMath.calcBorrowIndex(2 * MathUtils.ONE_18_DP, ONE_PERCENT_PER_SECOND_BORROW_RATE, 1), 2.02e18);
    }

    /// @dev Starts one unit above par, not at par: at par the division is exact, leaving no fraction to round and the
    ///      rounding mode unobservable. One unit above, the exact product is `1e18 + 2` plus a fraction, which rounds
    ///      up to `1e18 + 3` rather than truncating to `1e18 + 2`.
    function test_calcBorrowIndex_RoundsUp() public pure {
        assertEq(
            InterestMath.calcBorrowIndex(MathUtils.ONE_18_DP + 1, MathUtils.SECONDS_IN_YEAR, 1), MathUtils.ONE_18_DP + 3
        );
    }

    // toActualDebt()

    function test_toActualDebt_ReturnsScaledAmountAtParIndex() public pure {
        assertEq(InterestMath.toActualDebt(AMOUNT, MathUtils.ONE_18_DP), AMOUNT);
    }

    function test_toActualDebt_ReturnsZeroWhenScaledAmountIsZero() public pure {
        assertEq(InterestMath.toActualDebt(0, 2 * MathUtils.ONE_18_DP), 0);
    }

    function test_toActualDebt_StatesDebtAtIndex() public pure {
        assertEq(InterestMath.toActualDebt(AMOUNT, 2 * MathUtils.ONE_18_DP), 2 * AMOUNT);
    }

    /// @dev One scaled unit at the smallest index above par owes a fraction over one unit, and rounds up to two.
    function test_toActualDebt_RoundsUp() public pure {
        assertEq(InterestMath.toActualDebt(1, MathUtils.ONE_18_DP + 1), 2);
    }

    // toScaledDebt()

    function test_toScaledDebt_ReturnsAmountAtParIndex() public pure {
        assertEq(InterestMath.toScaledDebt(AMOUNT, MathUtils.ONE_18_DP), AMOUNT);
    }

    function test_toScaledDebt_ReturnsZeroWhenAmountIsZero() public pure {
        assertEq(InterestMath.toScaledDebt(0, 2 * MathUtils.ONE_18_DP), 0);
    }

    function test_toScaledDebt_NormalisesAmountByIndex() public pure {
        assertEq(InterestMath.toScaledDebt(2 * AMOUNT, 2 * MathUtils.ONE_18_DP), AMOUNT);
    }

    /// @dev One unit of new debt is worth a fraction under one scaled unit, and rounds up to a whole one so the stored
    ///      debt is never below what was borrowed.
    function test_toScaledDebt_RoundsUp() public pure {
        assertEq(InterestMath.toScaledDebt(1, MathUtils.ONE_18_DP + 1), 1);
    }

    /// @dev Rounding up is not free: a scaled unit states a whole index of debt, so borrowing one unit at an index of
    ///      two leaves two units owed.
    function test_toScaledDebt_OverstatesDebtByUpToOneIndex() public pure {
        uint256 borrowIndex = 2 * MathUtils.ONE_18_DP;

        assertEq(InterestMath.toActualDebt(InterestMath.toScaledDebt(1, borrowIndex), borrowIndex), 2);
    }

    // toScaledRepayment()

    function test_toScaledRepayment_ReturnsAmountAtParIndex() public pure {
        assertEq(InterestMath.toScaledRepayment(AMOUNT, MathUtils.ONE_18_DP), AMOUNT);
    }

    function test_toScaledRepayment_ReturnsZeroWhenAmountIsZero() public pure {
        assertEq(InterestMath.toScaledRepayment(0, 2 * MathUtils.ONE_18_DP), 0);
    }

    function test_toScaledRepayment_NormalisesAmountByIndex() public pure {
        assertEq(InterestMath.toScaledRepayment(2 * AMOUNT, 2 * MathUtils.ONE_18_DP), AMOUNT);
    }

    /// @dev One unit of repayment is worth a fraction under one scaled unit, and rounds down to nothing, so it never
    ///      clears more debt than it covers.
    function test_toScaledRepayment_RoundsDown() public pure {
        assertEq(InterestMath.toScaledRepayment(1, MathUtils.ONE_18_DP + 1), 0);
    }

    /// @dev The property that lets a position close to exactly zero: repaying the full debt a scaled amount states
    ///      clears that scaled amount in full, despite `toActualDebt` having rounded the debt up.
    function test_toScaledRepayment_InvertsToActualDebt() public pure {
        uint256 borrowIndex = MathUtils.ONE_18_DP + 1;

        assertEq(InterestMath.toScaledRepayment(InterestMath.toActualDebt(AMOUNT, borrowIndex), borrowIndex), AMOUNT);
    }

    // calcAccruedInterest()

    function test_calcAccruedInterest_ReturnsZeroWhenBorrowIndexIsUnchanged() public pure {
        assertEq(InterestMath.calcAccruedInterest(AMOUNT, 2 * MathUtils.ONE_18_DP, 2 * MathUtils.ONE_18_DP), 0);
    }

    function test_calcAccruedInterest_ReturnsZeroWhenScaledAmountIsZero() public pure {
        assertEq(InterestMath.calcAccruedInterest(0, MathUtils.ONE_18_DP, 2 * MathUtils.ONE_18_DP), 0);
    }

    function test_calcAccruedInterest_ReturnsGrowthInDebtOwed() public pure {
        assertEq(InterestMath.calcAccruedInterest(AMOUNT, MathUtils.ONE_18_DP, 2 * MathUtils.ONE_18_DP), AMOUNT);
    }

    /// @dev Both ends round up, so the accrual is the growth in the debt the pool reports rather than the index delta
    ///      rounded up on its own: one scaled unit moving from one unit above par to two owes two either way, so
    ///      nothing accrues, where rounding the delta up would have charged a unit.
    function test_calcAccruedInterest_MatchesGrowthInStatedDebtNotRoundedUpIndexDelta() public pure {
        uint256 prevBorrowIndex = MathUtils.ONE_18_DP + 1;
        uint256 newBorrowIndex = MathUtils.ONE_18_DP + 2;

        assertEq(InterestMath.toActualDebt(1, prevBorrowIndex), 2);
        assertEq(InterestMath.toActualDebt(1, newBorrowIndex), 2);
        assertEq(InterestMath.calcAccruedInterest(1, prevBorrowIndex, newBorrowIndex), 0);
    }

    // calcRetained()

    function test_calcRetained_ReturnsZeroWhenAccruedInterestIsZero() public pure {
        assertEq(InterestMath.calcRetained(0, RETENTION_RATE), 0);
    }

    function test_calcRetained_ReturnsZeroWhenRetentionRateIsZero() public pure {
        assertEq(InterestMath.calcRetained(AMOUNT, 0), 0);
    }

    function test_calcRetained_ReturnsAllAccruedInterestWhenRetentionRateIsOne() public pure {
        assertEq(InterestMath.calcRetained(AMOUNT, MathUtils.ONE_18_DP), AMOUNT);
    }

    function test_calcRetained_ReturnsRetainedShare() public pure {
        assertEq(InterestMath.calcRetained(AMOUNT, RETENTION_RATE), 200e18);
    }

    /// @dev A retained share of a fraction under one unit rounds down to nothing, keeping the dust in the pool.
    function test_calcRetained_RoundsDown() public pure {
        assertEq(InterestMath.calcRetained(1, MathUtils.ONE_18_DP - 1), 0);
    }

    // calcFees()

    function test_calcFees_ReturnsZeroWhenAccruedInterestIsZero() public pure {
        (uint256 operatorFee, uint256 onlendFee) = InterestMath.calcFees(0, 0, FIXED_FEE_BPS, SPLIT_FEE_BPS);

        assertEq(operatorFee, 0);
        assertEq(onlendFee, 0);
    }

    /// @dev 10% of 1000e18 is a 100e18 fixed fee; 25% of the 200e18 retained is a 50e18 split fee.
    function test_calcFees_AddsFixedFeeAndSplitsRetention() public pure {
        (uint256 operatorFee, uint256 onlendFee) = InterestMath.calcFees(AMOUNT, 200e18, FIXED_FEE_BPS, SPLIT_FEE_BPS);

        assertEq(operatorFee, 150e18);
        assertEq(onlendFee, 150e18);
    }

    /// @dev With all interest retained, the 100e18 fixed fee leaves 900e18 of retention, 25% of which is split off.
    function test_calcFees_CapsRetentionWhenRetentionAndFixedFeeExceedInterest() public pure {
        (uint256 operatorFee, uint256 onlendFee) = InterestMath.calcFees(AMOUNT, AMOUNT, FIXED_FEE_BPS, SPLIT_FEE_BPS);

        assertEq(operatorFee, 675e18);
        assertEq(onlendFee, 325e18);
    }

    function test_calcFees_GivesOnlendAllInterestWhenFixedFeeIsMax() public pure {
        (uint256 operatorFee, uint256 onlendFee) = InterestMath.calcFees(AMOUNT, 200e18, MathUtils.ONE_4_DP, 0);

        assertEq(operatorFee, 0);
        assertEq(onlendFee, AMOUNT);
    }

    /// @dev Both of Onlend's fees on a single unit round down to nothing, leaving the unit with the operator.
    function test_calcFees_RoundsOnlendFeeDown() public pure {
        (uint256 operatorFee, uint256 onlendFee) =
            InterestMath.calcFees(1, 1, MathUtils.ONE_4_DP - 1, MathUtils.ONE_4_DP - 1);

        assertEq(operatorFee, 1);
        assertEq(onlendFee, 0);
    }

    // calcAnnualInterest()

    function test_calcAnnualInterest_ReturnsZeroWhenTotalDebtIsZero() public pure {
        assertEq(InterestMath.calcAnnualInterest(0, BORROW_RATE), 0);
    }

    function test_calcAnnualInterest_ReturnsZeroWhenBorrowRateIsZero() public pure {
        assertEq(InterestMath.calcAnnualInterest(AMOUNT, 0), 0);
    }

    function test_calcAnnualInterest_ReturnsAnnualInterest() public pure {
        assertEq(InterestMath.calcAnnualInterest(AMOUNT, BORROW_RATE), 100e18);
    }

    /// @dev Interest of a fraction under one unit rounds down to nothing, so depositors are never promised more than
    ///      the debt side generated.
    function test_calcAnnualInterest_RoundsDown() public pure {
        assertEq(InterestMath.calcAnnualInterest(1, MathUtils.ONE_18_DP - 1), 0);
    }

    // calcDepositInterestRate()

    function test_calcDepositInterestRate_ReturnsZeroWhenDepositorAssetsAreZero() public pure {
        assertEq(InterestMath.calcDepositInterestRate(100e18, 0), 0);
    }

    function test_calcDepositInterestRate_ReturnsZeroWhenDepositorYieldIsZero() public pure {
        assertEq(InterestMath.calcDepositInterestRate(0, 1000e18), 0);
    }

    function test_calcDepositInterestRate_ReturnsAnnualisedRate() public pure {
        assertEq(InterestMath.calcDepositInterestRate(80e18, 1000e18), 0.08e18);
    }

    function test_calcDepositInterestRate_RoundsDown() public pure {
        assertEq(InterestMath.calcDepositInterestRate(1, 3), 333_333_333_333_333_333);
    }
}
