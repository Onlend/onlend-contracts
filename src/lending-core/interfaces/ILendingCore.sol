// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {IPool} from "../../pool/interfaces/IPool.sol";

/// @title Lending Core Interface
/// @notice Entry point for lending operations: routes user collateral, borrow, repay, and liquidation actions across
///         the listed pools, enforcing loan health on the resulting positions.
interface ILendingCore is IERC165, IVersioned {
    /// @notice A single position within a loan, held either as collateral supplied to `pool` or as an amount borrowed
    ///         from it. Which of the two it is comes from the context the position appears in.
    /// @param pool The pool the position is held in.
    /// @param amount The underlying token amount supplied or owed (not the share amount).
    struct LoanPosition {
        IPool pool;
        uint256 amount;
    }

    /// @notice A user's loan, comprising all of its collateral and borrow positions.
    /// @param account The account that owns the loan.
    /// @param collaterals The loan's collateral positions.
    /// @param borrows The loan's borrow positions.
    struct Loan {
        address account;
        LoanPosition[] collaterals;
        LoanPosition[] borrows;
    }

    /// @notice Deposits collateral into `pool` on behalf of `onBehalfOf`, crediting it to `receiver`'s loan.
    /// @dev Exactly one of `assets` or `shares` must be non-zero; the other must be zero. In both cases the underlying
    ///      is pulled from the caller; the two arguments only differ in the unit the deposit amount is denominated in
    ///      (underlying units vs. share units), with the other derived.
    /// @param pool The pool to supply collateral to.
    /// @param assets The deposit amount denominated in underlying units.
    /// @param shares The deposit amount denominated in share units.
    /// @param onBehalfOf The account whose loan is credited with the collateral.
    /// @return assetsDeposited Underlying amount actually deposited.
    /// @return sharesMinted Pool shares the deposit minted, or zero for a pool without shares.
    function depositCollateral(IPool pool, uint256 assets, uint256 shares, address onBehalfOf)
        external
        returns (uint256 assetsDeposited, uint256 sharesMinted);

    /// @notice Withdraws collateral from `pool`, debiting `onBehalfOf`'s loan and sending the proceeds to `receiver`.
    /// @dev Exactly one of `assets` or `shares` must be non-zero; the other must be zero. In both cases the underlying
    ///      is sent to `receiver`; the two arguments only differ in the unit the withdrawal amount is denominated in
    ///      (underlying units vs. share units), with the other derived.
    /// @param pool The pool to withdraw collateral from.
    /// @param assets The withdrawal amount denominated in underlying units.
    /// @param shares The withdrawal amount denominated in share units.
    /// @param onBehalfOf The account whose loan is being withdrawn from.
    /// @param receiver The account that receives the withdrawn underlying.
    /// @return assetsWithdrawn Underlying amount actually withdrawn.
    /// @return sharesBurned Pool shares the withdrawal burned, or zero for a pool without shares.
    function withdrawCollateral(IPool pool, uint256 assets, uint256 shares, address onBehalfOf, address receiver)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesBurned);

    /// @notice Borrows `amount` of underlying from `pool` on behalf of `onBehalfOf`, sending proceeds to `receiver`.
    /// @dev Records the debt against `onBehalfOf`'s loan and reverts if the resulting loan is unhealthy.
    /// @param pool The pool to borrow from.
    /// @param amount The borrow amount denominated in underlying units.
    /// @param onBehalfOf The account whose loan is assigned the debt.
    /// @param receiver The account that receives the borrowed underlying.
    function borrow(IPool pool, uint256 amount, address onBehalfOf, address receiver) external;

    /// @notice Repays up to `amount` of `onBehalfOf`'s debt using the caller's funds.
    /// @param pool The pool to repay debt in.
    /// @param amount The repayment amount denominated in underlying units, capped by `onBehalfOf`'s debt.
    /// @param onBehalfOf The account whose debt is repaid.
    /// @return repayment Actual underlying amount repaid.
    function repay(IPool pool, uint256 amount, address onBehalfOf) external returns (uint256 repayment);

    /// @notice Liquidates `violator`'s unhealthy loan, seizing collateral and repaying borrows on the caller's behalf.
    /// @dev Reverts if the violator's loan is not liquidatable. Each pool settles the seizure out of the position
    ///      rather than out of its available liquidity, so what the caller is paid in depends on the pool.
    /// @param violator The account whose loan is being liquidated.
    /// @param reqCols The requested collateral positions to seize from the loan. The amounts are interpreted as exact
    ///        or minimum values depending on the liquidation engine implementation.
    /// @param reqBors The requested borrow positions to repay on the loan. The amounts are interpreted as exact or
    ///        maximum values depending on the liquidation engine implementation.
    function liquidate(address violator, LoanPosition[] calldata reqCols, LoanPosition[] calldata reqBors) external;

    /// @notice Sets the metadata associated with the lending app.
    /// @param jsonPayload JSON metadata payload.
    function setMetadata(string calldata jsonPayload) external;

    /// @notice The loan evaluator used to assess loan health.
    /// @return The address of the current loan evaluator.
    function loanEvaluator() external view returns (address);

    /// @notice The liquidation engine used to compute liquidations.
    /// @return The address of the current liquidation engine.
    function liquidationEngine() external view returns (address);

    /// @notice The loan of `account`, as the health and liquidation checks see it.
    /// @dev Built from the account's positions across every listed pool, deprecated pools included, since positions on
    ///      them still back or burden the loan. Zero positions are omitted.
    /// @param account The account whose loan to build.
    /// @return loan The account's loan.
    function loanOf(address account) external view returns (Loan memory loan);
}
