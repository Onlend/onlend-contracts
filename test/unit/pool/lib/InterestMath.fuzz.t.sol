// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {InterestMath} from "src/pool/lib/InterestMath.sol";

contract InterestMathFuzzTest is Test {
    // Minimum annual 18dp rate whose per-second rate does not round to zero: 1 * seconds per year.
    uint256 constant MIN_ACCRUING_BORROW_RATE = MathUtils.SECONDS_IN_YEAR;

    // Bounds chosen so index/debt math stays within uint256 across the fuzzed elapsed window.
    uint256 constant MAX_BORROW_RATE = 10e18; // 1000% APR
    uint256 constant MAX_BORROW_INDEX = type(uint128).max;
    // Starting index for tests that actually compound: high enough to be well past par, low enough that the maximum
    // rate over the maximum window (a factor of about e^100) still fits in uint256.
    uint256 constant MAX_ACCRUING_BORROW_INDEX = 1e24;
    uint256 constant MAX_SCALED_AMOUNT = type(uint128).max;
    uint256 constant MAX_ELAPSED = 10 * 365 days;

    // calcUtilisation()

    function testFuzz_calcUtilisation_IsAtMostOne(uint256 idleLiquidity, uint256 totalDebt) public pure {
        idleLiquidity = bound(idleLiquidity, 0, type(uint256).max / 2);
        totalDebt = bound(totalDebt, 0, type(uint256).max / 2);

        assertLe(InterestMath.calcUtilisation(idleLiquidity, totalDebt), MathUtils.ONE_18_DP);
    }

    function testFuzz_calcUtilisation_ReturnsOneWhenThereIsNoIdleLiquidity(uint256 totalDebt) public pure {
        totalDebt = bound(totalDebt, 1, type(uint256).max);

        assertEq(InterestMath.calcUtilisation(0, totalDebt), MathUtils.ONE_18_DP);
    }

    /// @dev Bounds the numerator to 256 bits so the floor-division remainder can be checked independently without
    ///      reproducing the implementation's full-precision multiplication.
    function testFuzz_calcUtilisation_RoundsDown(uint256 idleLiquidity, uint256 totalDebt) public pure {
        totalDebt = bound(totalDebt, 0, type(uint256).max / MathUtils.ONE_18_DP);
        idleLiquidity = bound(idleLiquidity, totalDebt == 0 ? 1 : 0, type(uint256).max - totalDebt);
        uint256 numerator = totalDebt * MathUtils.ONE_18_DP;
        uint256 totalLiquidity = idleLiquidity + totalDebt;

        uint256 utilisation = InterestMath.calcUtilisation(idleLiquidity, totalDebt);
        uint256 borrowedLiquidity = utilisation * totalLiquidity;

        assertLe(borrowedLiquidity, numerator);
        assertLt(numerator - borrowedLiquidity, totalLiquidity);
    }

    // calcBorrowIndex()

    function testFuzz_calcBorrowIndex_ReturnsPreviousBorrowIndexWhenBorrowRateIsZero(
        uint256 prevBorrowIndex,
        uint256 elapsed
    ) public pure {
        prevBorrowIndex = bound(prevBorrowIndex, MathUtils.ONE_18_DP, MAX_BORROW_INDEX);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);

        assertEq(InterestMath.calcBorrowIndex(prevBorrowIndex, 0, elapsed), prevBorrowIndex);
    }

    function testFuzz_calcBorrowIndex_ReturnsPreviousBorrowIndexWhenElapsedIsZero(
        uint256 prevBorrowIndex,
        uint256 borrowRate
    ) public pure {
        prevBorrowIndex = bound(prevBorrowIndex, MathUtils.ONE_18_DP, MAX_BORROW_INDEX);
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);

        assertEq(InterestMath.calcBorrowIndex(prevBorrowIndex, borrowRate, 0), prevBorrowIndex);
    }

    function testFuzz_calcBorrowIndex_DoesNotAccrueWhenBorrowRateTruncatesToZeroPerSecond(
        uint256 prevBorrowIndex,
        uint256 borrowRate,
        uint256 elapsed
    ) public pure {
        prevBorrowIndex = bound(prevBorrowIndex, MathUtils.ONE_18_DP, MAX_BORROW_INDEX);
        borrowRate = bound(borrowRate, 1, MIN_ACCRUING_BORROW_RATE - 1);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);

        assertEq(InterestMath.calcBorrowIndex(prevBorrowIndex, borrowRate, elapsed), prevBorrowIndex);
    }

    function testFuzz_calcBorrowIndex_IncreasesWhenBorrowRatePerSecondIsPositive(uint256 borrowRate, uint256 elapsed)
        public
        pure
    {
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MAX_BORROW_RATE);
        elapsed = bound(elapsed, 1, MAX_ELAPSED);

        assertGt(InterestMath.calcBorrowIndex(MathUtils.ONE_18_DP, borrowRate, elapsed), MathUtils.ONE_18_DP);
    }

    function testFuzz_calcBorrowIndex_NeverReturnsBelowPreviousBorrowIndex(
        uint256 prevBorrowIndex,
        uint256 borrowRate,
        uint256 elapsed
    ) public pure {
        prevBorrowIndex = bound(prevBorrowIndex, MathUtils.ONE_18_DP, MAX_ACCRUING_BORROW_INDEX);
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);

        assertGe(InterestMath.calcBorrowIndex(prevBorrowIndex, borrowRate, elapsed), prevBorrowIndex);
    }

    /// @dev Compounding is mathematically path-independent — accruing over one window equals accruing over any split
    ///      of it — but the implementation is not: `exponentialBySquaring` floors on every squaring, so how far it
    ///      underestimates depends on the exponent's bit pattern, and splitting a window changes that pattern. The
    ///      divergence has no fixed direction (elapsed 2 split 1+1 lands a unit high, because an exponent of one never
    ///      squares; elapsed 50 split 25+25 lands two units low, because each half floors more often than the whole).
    ///      Its size is what matters: the two paths agree to 16 significant figures, so how often accrual is driven
    ///      does not change what borrowers owe.
    function testFuzz_calcBorrowIndex_SplittingElapsedBarelyChangesResult(uint256 borrowRate, uint256 elapsed)
        public
        pure
    {
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MAX_BORROW_RATE);
        elapsed = bound(elapsed, 2, MAX_ELAPSED);
        uint256 firstHalf = elapsed / 2;

        uint256 oneStep = InterestMath.calcBorrowIndex(MathUtils.ONE_18_DP, borrowRate, elapsed);
        uint256 twoSteps = InterestMath.calcBorrowIndex(
            InterestMath.calcBorrowIndex(MathUtils.ONE_18_DP, borrowRate, firstHalf), borrowRate, elapsed - firstHalf
        );

        assertApproxEqRel(twoSteps, oneStep, 1e2);
    }

    // toActualDebt()

    function testFuzz_toActualDebt_NeverBelowScaledAmount(uint256 scaledAmount, uint256 borrowIndex) public pure {
        scaledAmount = bound(scaledAmount, 0, MAX_SCALED_AMOUNT);
        borrowIndex = bound(borrowIndex, MathUtils.ONE_18_DP, MAX_BORROW_INDEX);

        assertGe(InterestMath.toActualDebt(scaledAmount, borrowIndex), scaledAmount);
    }

    function testFuzz_toActualDebt_IncreasesWithBorrowIndex(
        uint256 scaledAmount,
        uint256 borrowIndex,
        uint256 laterBorrowIndex
    ) public pure {
        scaledAmount = bound(scaledAmount, 1, MAX_SCALED_AMOUNT);
        borrowIndex = bound(borrowIndex, MathUtils.ONE_18_DP, MAX_BORROW_INDEX - 1);
        laterBorrowIndex = bound(laterBorrowIndex, borrowIndex, MAX_BORROW_INDEX);

        assertGe(
            InterestMath.toActualDebt(scaledAmount, laterBorrowIndex),
            InterestMath.toActualDebt(scaledAmount, borrowIndex)
        );
    }

    // toScaledDebt()

    /// @dev Creating debt then reading it back never understates what was borrowed.
    function testFuzz_toScaledDebt_RoundTripNeverUnderstatesDebt(uint256 amount, uint256 borrowIndex) public pure {
        amount = bound(amount, 0, MAX_SCALED_AMOUNT);
        borrowIndex = bound(borrowIndex, MathUtils.ONE_18_DP, MAX_BORROW_INDEX);

        assertGe(InterestMath.toActualDebt(InterestMath.toScaledDebt(amount, borrowIndex), borrowIndex), amount);
    }

    /// @dev The two conversions are the same division rounded opposite ways, so they differ by at most one scaled
    ///      unit: zero when the index divides the amount evenly, one otherwise.
    function testFuzz_toScaledDebt_ExceedsToScaledRepaymentByAtMostOne(uint256 amount, uint256 borrowIndex)
        public
        pure
    {
        amount = bound(amount, 0, MAX_SCALED_AMOUNT);
        borrowIndex = bound(borrowIndex, MathUtils.ONE_18_DP, MAX_BORROW_INDEX);

        assertLe(
            InterestMath.toScaledDebt(amount, borrowIndex) - InterestMath.toScaledRepayment(amount, borrowIndex), 1
        );
    }

    // toScaledRepayment()

    /// @dev The property a position closing to zero depends on: repaying exactly the debt a scaled amount states
    ///      clears that scaled amount in full, at any borrow index.
    function testFuzz_toScaledRepayment_InvertsToActualDebt(uint256 scaledAmount, uint256 borrowIndex) public pure {
        scaledAmount = bound(scaledAmount, 0, MAX_SCALED_AMOUNT);
        borrowIndex = bound(borrowIndex, MathUtils.ONE_18_DP, MAX_BORROW_INDEX);

        assertEq(
            InterestMath.toScaledRepayment(InterestMath.toActualDebt(scaledAmount, borrowIndex), borrowIndex),
            scaledAmount
        );
    }

    /// @dev A partial repayment never clears more scaled debt than repaying the whole balance would.
    function testFuzz_toScaledRepayment_NeverClearsMoreThanFullBalance(
        uint256 scaledAmount,
        uint256 borrowIndex,
        uint256 repayment
    ) public pure {
        scaledAmount = bound(scaledAmount, 0, MAX_SCALED_AMOUNT);
        borrowIndex = bound(borrowIndex, MathUtils.ONE_18_DP, MAX_BORROW_INDEX);
        repayment = bound(repayment, 0, InterestMath.toActualDebt(scaledAmount, borrowIndex));

        assertLe(InterestMath.toScaledRepayment(repayment, borrowIndex), scaledAmount);
    }

    // calcAccruedInterest()

    /// @dev Differencing two rounded-up figures never charges more than rounding the index delta up once would, and
    ///      falls short of it by at most a unit — so the choice of formula costs borrowers nothing.
    function testFuzz_calcAccruedInterest_NeverExceedsRoundedUpIndexDelta(
        uint256 scaledAmount,
        uint256 prevBorrowIndex,
        uint256 newBorrowIndex
    ) public pure {
        scaledAmount = bound(scaledAmount, 0, MAX_SCALED_AMOUNT);
        prevBorrowIndex = bound(prevBorrowIndex, MathUtils.ONE_18_DP, MAX_BORROW_INDEX);
        newBorrowIndex = bound(newBorrowIndex, prevBorrowIndex, MAX_BORROW_INDEX);
        uint256 roundedUpIndexDelta =
            Math.mulDiv(scaledAmount, newBorrowIndex - prevBorrowIndex, MathUtils.ONE_18_DP, Math.Rounding.Ceil);

        uint256 accruedInterest = InterestMath.calcAccruedInterest(scaledAmount, prevBorrowIndex, newBorrowIndex);

        assertLe(accruedInterest, roundedUpIndexDelta);
        assertGe(accruedInterest + 1, roundedUpIndexDelta);
    }

    function testFuzz_calcAccruedInterest_ReturnsZeroWhenBorrowIndexIsUnchanged(
        uint256 scaledAmount,
        uint256 borrowIndex
    ) public pure {
        scaledAmount = bound(scaledAmount, 0, MAX_SCALED_AMOUNT);
        borrowIndex = bound(borrowIndex, MathUtils.ONE_18_DP, MAX_BORROW_INDEX);

        assertEq(InterestMath.calcAccruedInterest(scaledAmount, borrowIndex, borrowIndex), 0);
    }

    function testFuzz_calcAccruedInterest_IncreasesWithNewBorrowIndex(
        uint256 scaledAmount,
        uint256 prevBorrowIndex,
        uint256 newBorrowIndex,
        uint256 higherBorrowIndex
    ) public pure {
        scaledAmount = bound(scaledAmount, 0, MAX_SCALED_AMOUNT);
        prevBorrowIndex = bound(prevBorrowIndex, MathUtils.ONE_18_DP, MAX_BORROW_INDEX);
        newBorrowIndex = bound(newBorrowIndex, prevBorrowIndex, MAX_BORROW_INDEX);
        higherBorrowIndex = bound(higherBorrowIndex, newBorrowIndex, MAX_BORROW_INDEX);

        assertGe(
            InterestMath.calcAccruedInterest(scaledAmount, prevBorrowIndex, higherBorrowIndex),
            InterestMath.calcAccruedInterest(scaledAmount, prevBorrowIndex, newBorrowIndex)
        );
    }

    // calcRetained()

    function testFuzz_calcRetained_NeverExceedsAccruedInterest(uint256 accruedInterest, uint256 retentionRate)
        public
        pure
    {
        accruedInterest = bound(accruedInterest, 0, MAX_SCALED_AMOUNT);
        retentionRate = bound(retentionRate, 0, MathUtils.ONE_18_DP);

        assertLe(InterestMath.calcRetained(accruedInterest, retentionRate), accruedInterest);
    }

    function testFuzz_calcRetained_ReturnsZeroWhenRetentionRateIsZero(uint256 accruedInterest) public pure {
        accruedInterest = bound(accruedInterest, 0, MAX_SCALED_AMOUNT);

        assertEq(InterestMath.calcRetained(accruedInterest, 0), 0);
    }

    function testFuzz_calcRetained_ReturnsAllAccruedInterestWhenRetentionRateIsOne(uint256 accruedInterest)
        public
        pure
    {
        accruedInterest = bound(accruedInterest, 0, MAX_SCALED_AMOUNT);

        assertEq(InterestMath.calcRetained(accruedInterest, MathUtils.ONE_18_DP), accruedInterest);
    }

    // calcFees()

    /// @dev The two fees are computed separately, so this pins the one relationship that must hold between them:
    ///      together they never take more than the interest accrued.
    function testFuzz_calcFees_NeverExceedsAccruedInterest(
        uint256 accrued,
        uint256 retained,
        uint256 fixedFeeBps,
        uint256 splitFeeBps
    ) public pure {
        accrued = bound(accrued, 0, MAX_SCALED_AMOUNT);
        retained = bound(retained, 0, accrued);
        fixedFeeBps = bound(fixedFeeBps, 0, MathUtils.ONE_4_DP);
        splitFeeBps = bound(splitFeeBps, 0, MathUtils.ONE_4_DP);

        (uint256 operatorFee, uint256 onlendFee) = InterestMath.calcFees(accrued, retained, fixedFeeBps, splitFeeBps);

        assertLe(operatorFee + onlendFee, accrued);
    }

    function testFuzz_calcFees_GivesOperatorAllRetentionWhenFeesAreZero(uint256 accrued, uint256 retained) public pure {
        accrued = bound(accrued, 0, MAX_SCALED_AMOUNT);
        retained = bound(retained, 0, accrued);

        (uint256 operatorFee, uint256 onlendFee) = InterestMath.calcFees(accrued, retained, 0, 0);

        assertEq(operatorFee, retained);
        assertEq(onlendFee, 0);
    }

    function testFuzz_calcFees_ReturnsZeroOperatorFeeWhenSplitFeeIsMax(
        uint256 accrued,
        uint256 retained,
        uint256 fixedFeeBps
    ) public pure {
        accrued = bound(accrued, 0, MAX_SCALED_AMOUNT);
        retained = bound(retained, 0, accrued);
        fixedFeeBps = bound(fixedFeeBps, 0, MathUtils.ONE_4_DP);

        (uint256 operatorFee,) = InterestMath.calcFees(accrued, retained, fixedFeeBps, MathUtils.ONE_4_DP);

        assertEq(operatorFee, 0);
    }

    function testFuzz_calcFees_SplitsExactlyRetentionWhenFixedFeeIsZero(
        uint256 accrued,
        uint256 retained,
        uint256 splitFeeBps
    ) public pure {
        accrued = bound(accrued, 0, MAX_SCALED_AMOUNT);
        retained = bound(retained, 0, accrued);
        splitFeeBps = bound(splitFeeBps, 0, MathUtils.ONE_4_DP);

        (uint256 operatorFee, uint256 onlendFee) = InterestMath.calcFees(accrued, retained, 0, splitFeeBps);

        assertEq(operatorFee + onlendFee, retained);
    }

    /// @dev With all interest retained, depositors are owed nothing, so the fixed fee comes out of the retention and
    ///      the two fees together take everything.
    function testFuzz_calcFees_TakesAllInterestWhenAllRetained(
        uint256 accrued,
        uint256 fixedFeeBps,
        uint256 splitFeeBps
    ) public pure {
        accrued = bound(accrued, 0, MAX_SCALED_AMOUNT);
        fixedFeeBps = bound(fixedFeeBps, 0, MathUtils.ONE_4_DP);
        splitFeeBps = bound(splitFeeBps, 0, MathUtils.ONE_4_DP);

        (uint256 operatorFee, uint256 onlendFee) = InterestMath.calcFees(accrued, accrued, fixedFeeBps, splitFeeBps);

        assertEq(operatorFee + onlendFee, accrued);
    }

    /// @dev Onlend's fixed fee is taken before the retention is capped, so no amount of retention can eat into it.
    function testFuzz_calcFees_OnlendFeeNeverBelowFixedFeeAlone(
        uint256 accrued,
        uint256 retained,
        uint256 fixedFeeBps,
        uint256 splitFeeBps
    ) public pure {
        accrued = bound(accrued, 0, MAX_SCALED_AMOUNT);
        retained = bound(retained, 0, accrued);
        fixedFeeBps = bound(fixedFeeBps, 0, MathUtils.ONE_4_DP);
        splitFeeBps = bound(splitFeeBps, 0, MathUtils.ONE_4_DP);

        (, uint256 onlendFee) = InterestMath.calcFees(accrued, retained, fixedFeeBps, splitFeeBps);
        (, uint256 fixedFeeAlone) = InterestMath.calcFees(accrued, 0, fixedFeeBps, 0);

        assertGe(onlendFee, fixedFeeAlone);
    }

    function testFuzz_calcFees_MovesFeeFromOperatorToOnlendAsSplitFeeRises(
        uint256 accrued,
        uint256 retained,
        uint256 fixedFeeBps,
        uint256 splitFeeBps,
        uint256 higherSplitFeeBps
    ) public pure {
        accrued = bound(accrued, 0, MAX_SCALED_AMOUNT);
        retained = bound(retained, 0, accrued);
        fixedFeeBps = bound(fixedFeeBps, 0, MathUtils.ONE_4_DP);
        splitFeeBps = bound(splitFeeBps, 0, MathUtils.ONE_4_DP);
        higherSplitFeeBps = bound(higherSplitFeeBps, splitFeeBps, MathUtils.ONE_4_DP);

        (uint256 operatorFee, uint256 onlendFee) = InterestMath.calcFees(accrued, retained, fixedFeeBps, splitFeeBps);
        (uint256 higherOperatorFee, uint256 higherOnlendFee) =
            InterestMath.calcFees(accrued, retained, fixedFeeBps, higherSplitFeeBps);

        assertLe(higherOperatorFee, operatorFee);
        assertGe(higherOnlendFee, onlendFee);
    }

    function testFuzz_calcFees_MovesFeeFromOperatorToOnlendAsFixedFeeRises(
        uint256 accrued,
        uint256 retained,
        uint256 fixedFeeBps,
        uint256 higherFixedFeeBps,
        uint256 splitFeeBps
    ) public pure {
        accrued = bound(accrued, 0, MAX_SCALED_AMOUNT);
        retained = bound(retained, 0, accrued);
        fixedFeeBps = bound(fixedFeeBps, 0, MathUtils.ONE_4_DP);
        higherFixedFeeBps = bound(higherFixedFeeBps, fixedFeeBps, MathUtils.ONE_4_DP);
        splitFeeBps = bound(splitFeeBps, 0, MathUtils.ONE_4_DP);

        (uint256 operatorFee, uint256 onlendFee) = InterestMath.calcFees(accrued, retained, fixedFeeBps, splitFeeBps);
        (uint256 higherOperatorFee, uint256 higherOnlendFee) =
            InterestMath.calcFees(accrued, retained, higherFixedFeeBps, splitFeeBps);

        assertLe(higherOperatorFee, operatorFee);
        assertGe(higherOnlendFee, onlendFee);
    }

    // calcAnnualInterest()

    function testFuzz_calcAnnualInterest_ReturnsTotalDebtWhenBorrowRateIsOne(uint256 totalDebt) public pure {
        totalDebt = bound(totalDebt, 0, MAX_SCALED_AMOUNT);

        assertEq(InterestMath.calcAnnualInterest(totalDebt, MathUtils.ONE_18_DP), totalDebt);
    }

    function testFuzz_calcAnnualInterest_IncreasesWithBorrowRate(
        uint256 totalDebt,
        uint256 borrowRate,
        uint256 higherBorrowRate
    ) public pure {
        totalDebt = bound(totalDebt, 0, MAX_SCALED_AMOUNT);
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        higherBorrowRate = bound(higherBorrowRate, borrowRate, MAX_BORROW_RATE);

        assertGe(
            InterestMath.calcAnnualInterest(totalDebt, higherBorrowRate),
            InterestMath.calcAnnualInterest(totalDebt, borrowRate)
        );
    }

    function testFuzz_calcAnnualInterest_IncreasesWithTotalDebt(
        uint256 totalDebt,
        uint256 higherTotalDebt,
        uint256 borrowRate
    ) public pure {
        totalDebt = bound(totalDebt, 0, MAX_SCALED_AMOUNT);
        higherTotalDebt = bound(higherTotalDebt, totalDebt, MAX_SCALED_AMOUNT);
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);

        assertGe(
            InterestMath.calcAnnualInterest(higherTotalDebt, borrowRate),
            InterestMath.calcAnnualInterest(totalDebt, borrowRate)
        );
    }

    // calcDepositInterestRate()

    /// @dev Bounds the numerator to 256 bits so the floor-division remainder can be checked independently without
    ///      reproducing the implementation's full-precision multiplication.
    function testFuzz_calcDepositInterestRate_RoundsDown(uint256 depositorYield, uint256 depositorAssets) public pure {
        depositorYield = bound(depositorYield, 0, type(uint256).max / MathUtils.ONE_18_DP);
        depositorAssets = bound(depositorAssets, 1, type(uint256).max);
        uint256 numerator = depositorYield * MathUtils.ONE_18_DP;

        uint256 depositInterestRate = InterestMath.calcDepositInterestRate(depositorYield, depositorAssets);
        uint256 distributedYield = depositInterestRate * depositorAssets;

        assertLe(distributedYield, numerator);
        assertLt(numerator - distributedYield, depositorAssets);
    }
}
