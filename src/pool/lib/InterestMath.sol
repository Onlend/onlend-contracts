// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MathUtils} from "../../lib/MathUtils.sol";

/// @title  InterestMath
/// @notice Pure interest formulae, including index-normalised ("scaled") debt accounting.
/// @dev    Rounding is fixed per formula and stated on each return value.
library InterestMath {
    using Math for uint256;

    /// @notice Returns the share of total liquidity that is borrowed.
    /// @dev    Returns zero when there is no liquidity rather than dividing by zero.
    /// @param  idleLiquidity Liquidity available to borrow.
    /// @param  totalDebt     Outstanding debt.
    /// @return Utilisation, scaled to 18dp and rounded down.
    function calcUtilisation(uint256 idleLiquidity, uint256 totalDebt) internal pure returns (uint256) {
        uint256 totalLiquidity = idleLiquidity + totalDebt;
        if (totalLiquidity == 0) return 0;
        return totalDebt.mulDiv(MathUtils.ONE_18_DP, totalLiquidity, Math.Rounding.Floor);
    }

    /// @notice Compounds a borrow index forward over an elapsed period.
    /// @dev    `borrowRate` is truncated to a per-second rate before compounding, so the compounded factor slightly
    ///         underestimates continuous accrual. Returns `prevBorrowIndex` exactly when `elapsed` or `borrowRate` is
    ///         zero, so repeated updates within a block never inflate the index. Reverts once the compounded index
    ///         would exceed `uint256`, about 1.2e59 times its starting value of one, which takes over 13 years of
    ///         compounding at a 1,000% rate.
    /// @param  prevBorrowIndex Borrow index at the last update, scaled to 18dp.
    /// @param  borrowRate      Annual borrow rate applied over the period, scaled to 18dp.
    /// @param  elapsed         Seconds elapsed since the last update.
    /// @return Borrow index compounded over `elapsed`, rounded up.
    function calcBorrowIndex(uint256 prevBorrowIndex, uint256 borrowRate, uint256 elapsed)
        internal
        pure
        returns (uint256)
    {
        return prevBorrowIndex.mulDiv(
            MathUtils.exponentialBySquaring(
                MathUtils.ONE_18_DP + (borrowRate / MathUtils.SECONDS_IN_YEAR), elapsed, MathUtils.ONE_18_DP
            ),
            MathUtils.ONE_18_DP,
            Math.Rounding.Ceil
        );
    }

    /// @notice Converts a scaled debt amount into the debt actually owed at a borrow index.
    /// @param  scaledAmount Scaled debt amount.
    /// @param  borrowIndex  Borrow index to state the debt at, scaled to 18dp.
    /// @return Debt owed, rounded up.
    function toActualDebt(uint256 scaledAmount, uint256 borrowIndex) internal pure returns (uint256) {
        return scaledAmount.mulDiv(borrowIndex, MathUtils.ONE_18_DP, Math.Rounding.Ceil);
    }

    /// @notice Converts newly created debt into the scaled amount to store for it.
    /// @dev    Scaled amounts are coarser than actual debt once the index has compounded above one, so the debt read
    ///         back can exceed `amount` by up to `ceil((borrowIndex - 1) / MathUtils.ONE_18_DP)` units.
    /// @param  amount      Debt amount being created.
    /// @param  borrowIndex Borrow index the debt is created at, scaled to 18dp.
    /// @return Scaled amount to store, rounded up.
    function toScaledDebt(uint256 amount, uint256 borrowIndex) internal pure returns (uint256) {
        return amount.mulDiv(MathUtils.ONE_18_DP, borrowIndex, Math.Rounding.Ceil);
    }

    /// @notice Converts a repayment into the scaled amount of debt it clears.
    /// @dev    Inverts `toActualDebt` exactly, so repaying a full balance clears a position to zero rather than leaving
    ///         scaled dust behind. Holds in that direction only.
    /// @param  amount      Repayment amount.
    /// @param  borrowIndex Borrow index the repayment is made at, scaled to 18dp.
    /// @return Scaled amount of debt cleared, rounded down.
    function toScaledRepayment(uint256 amount, uint256 borrowIndex) internal pure returns (uint256) {
        return amount.mulDiv(MathUtils.ONE_18_DP, borrowIndex, Math.Rounding.Floor);
    }

    /// @notice Returns the interest accrued on a scaled debt amount as a borrow index moves forward.
    /// @dev    Differences the debt owed at each index rather than applying the index delta directly, so the accrual
    ///         matches the change in debt reported by `toActualDebt`. Assumes `newBorrowIndex >= prevBorrowIndex`,
    ///         which `calcBorrowIndex` guarantees for a forward move. Callers must uphold this; the result is undefined
    ///         otherwise.
    /// @param  scaledAmount    Scaled debt amount accruing the interest.
    /// @param  prevBorrowIndex Borrow index at the start of the period, scaled to 18dp.
    /// @param  newBorrowIndex  Borrow index at the end of the period, scaled to 18dp.
    /// @return Interest accrued over the period.
    function calcAccruedInterest(uint256 scaledAmount, uint256 prevBorrowIndex, uint256 newBorrowIndex)
        internal
        pure
        returns (uint256)
    {
        return toActualDebt(scaledAmount, newBorrowIndex) - toActualDebt(scaledAmount, prevBorrowIndex);
    }

    /// @notice Returns the share of accrued interest retained by the protocol.
    /// @dev    Assumes `retentionRate <= MathUtils.ONE_18_DP`. Callers must uphold this; a higher rate silently retains
    ///         more than was accrued.
    /// @param  accruedInterest Interest accrued over a period.
    /// @param  retentionRate   Fraction of accrued interest retained, scaled to 18dp.
    /// @return Retained amount, rounded down.
    function calcRetained(uint256 accruedInterest, uint256 retentionRate) internal pure returns (uint256) {
        return accruedInterest.mulDiv(retentionRate, MathUtils.ONE_18_DP, Math.Rounding.Floor);
    }

    /// @notice Splits the retained part of accrued interest, plus Onlend's fixed fee, into the operator's fee and
    ///         Onlend's fee.
    /// @dev    Onlend's fixed fee is taken in full first. The retention is then capped at what is left, so when the
    ///         retention rate and fixed fee together exceed 100% the shortfall comes out of the operator's cut rather
    ///         than Onlend's. Onlend's split fee is finally taken from the capped retention. Assumes `fixedFeeBps` and
    ///         `splitFeeBps` are at most `MathUtils.ONE_4_DP`. Callers must uphold this; the result is undefined
    ///         otherwise.
    /// @param  accruedInterest Interest accrued over a period.
    /// @param  retained        Part of `accruedInterest` retained under the retention rate.
    /// @param  fixedFeeBps     Share of `accruedInterest` taken by Onlend on top of the retention, in bps.
    /// @param  splitFeeBps     Share of the capped retention taken by Onlend, in bps.
    /// @return operatorFee Interest kept by the operator, rounded up.
    /// @return onlendFee   Interest taken by Onlend, rounded down.
    function calcFees(uint256 accruedInterest, uint256 retained, uint256 fixedFeeBps, uint256 splitFeeBps)
        internal
        pure
        returns (uint256 operatorFee, uint256 onlendFee)
    {
        uint256 fixedFee = accruedInterest.mulDiv(fixedFeeBps, MathUtils.ONE_4_DP, Math.Rounding.Floor);
        uint256 cappedRetained = Math.min(retained, accruedInterest - fixedFee);
        uint256 splitFee = cappedRetained.mulDiv(splitFeeBps, MathUtils.ONE_4_DP, Math.Rounding.Floor);

        return (cappedRetained - splitFee, fixedFee + splitFee);
    }

    /// @notice Returns the annualised interest a debt bucket generates.
    /// @param  totalDebt  Outstanding debt generating the interest.
    /// @param  borrowRate Annual borrow rate charged on the debt, scaled to 18dp.
    /// @return Annualised interest, rounded down.
    function calcAnnualInterest(uint256 totalDebt, uint256 borrowRate) internal pure returns (uint256) {
        return totalDebt.mulDiv(borrowRate, MathUtils.ONE_18_DP, Math.Rounding.Floor);
    }

    /// @notice Returns the annualised interest rate earned by depositors.
    /// @dev    Returns zero when `depositorAssets` is zero rather than dividing by zero.
    /// @param  depositorYield  Annualised yield generated for depositors.
    /// @param  depositorAssets Assets over which the depositor yield is distributed.
    /// @return Annualised deposit interest rate, scaled to 18dp and rounded down.
    function calcDepositInterestRate(uint256 depositorYield, uint256 depositorAssets) internal pure returns (uint256) {
        if (depositorAssets == 0) return 0;
        return depositorYield.mulDiv(MathUtils.ONE_18_DP, depositorAssets, Math.Rounding.Floor);
    }
}
