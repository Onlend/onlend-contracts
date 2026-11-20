// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {ILendingCore} from "../../lending-core/interfaces/ILendingCore.sol";
import {ILoanEvaluator} from "../../loan/interfaces/ILoanEvaluator.sol";

/// @title Liquidation Engine Interface
/// @notice Calculates the collateral to seize and borrows to repay when liquidating an unhealthy loan. The engine only
///         computes these values; it does not itself move any funds or mutate the loan.
/// @dev Every implementation that permits liquidation must uphold the following. The first two are properties of the
///      engine alone; the third also depends on how it is configured against the loan evaluator.
///
///      - Rounding favours the pool. However the engine prices what a repayment entitles the liquidator to, every
///        rounding must run against the liquidator, so the loan is never left owing more than the engine's own policy
///        would leave it under exact arithmetic. In particular, no non-zero collateral amount may be released against a
///        repayment the engine values at zero.
///      - Close-out stays reachable. While a loan is liquidatable, some sequence of requests must close out one side of
///        it, repaying all of its debt or seizing all of its remaining collateral. Closing it out must never be
///        conditional on a health the loan cannot attain.
///      - A newly liquidatable loan can be closed out without bad debt. Whatever the liquidator receives beyond what it
///        repays is the engine's incentive, and a liquidation that seizes the last of a loan's collateral pays it out
///        of the debt it leaves behind, which the pool's depositors bear on top of any genuine shortfall. The incentive
///        must therefore be small enough, against how the loan evaluator values the loan, that a loan which has only
///        just become liquidatable holds enough collateral to repay all of its debt with the incentive paid. Otherwise
///        a loan cannot be closed out without bad debt from the moment it becomes liquidatable, and anyone can extract
///        it by borrowing to their limit and liquidating themselves.
interface ILiquidationEngine is IVersioned, IERC165 {
    /// @notice Calculates the collateral to seize and borrows to repay for liquidating a loan, based on the requested
    ///         amounts. It does not itself move any funds or mutate the loan.
    /// @dev Reverts if the loan holds insufficient collateral to satisfy the requested seizure, or if the requested
    ///      repayment is insufficient. Whether a requested position the loan does not hold is rejected or ignored is
    ///      implementation-defined, as are any further requirements an implementation places on the requests, such as
    ///      rejecting a pool named twice.
    /// @param loan The loan to liquidate.
    /// @param health The loan's health before the liquidation, as `ILoanEvaluator.getLoanHealth` reports it. Passed in
    ///        rather than read from `loanEvaluator`, since a caller establishing that the loan is liquidatable has
    ///        already valued it.
    /// @param reqCols The requested collateral positions to seize from the loan. The amounts are interpreted as exact
    ///        or minimum values depending on the concrete implementation, which may also reserve `type(uint256).max` to
    ///        mean the whole of the loan's position in that pool.
    /// @param reqBors The requested borrow positions to repay on the loan. The amounts are interpreted as exact or
    ///        maximum values depending on the concrete implementation.
    /// @param loanEvaluator The evaluator used to assess the loan's health, allowing the engine to check what the
    ///        loan's health would be after the liquidation.
    /// @return colsToSeize The collateral positions the engine determined should be seized from the loan. Every entry
    ///         names a pool among the loan's collaterals with an amount no greater than the loan holds there. Not
    ///         bounded by `reqCols`: may name pools absent from it and amounts above the requested ones, since seizing
    ///         extra collateral only benefits the liquidator. The array may contain an entry with a zero amount.
    /// @return borsToRepay The borrow positions the engine determined should be repaid on the loan. Every entry names a
    ///         pool among the loan's borrows, and is bounded by `reqBors`: its pool is present in it with an amount no
    ///         greater than the one requested for that pool, so a liquidator can never be made to repay a position they
    ///         did not ask to repay. The array may contain an entry with a zero amount.
    function liquidate(
        ILendingCore.Loan calldata loan,
        uint256 health,
        ILendingCore.LoanPosition[] calldata reqCols,
        ILendingCore.LoanPosition[] calldata reqBors,
        ILoanEvaluator loanEvaluator
    ) external returns (ILendingCore.LoanPosition[] memory colsToSeize, ILendingCore.LoanPosition[] memory borsToRepay);
}
