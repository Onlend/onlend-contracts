// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {ILendingCore} from "../../lending-core/interfaces/ILendingCore.sol";

/// @title Loan Evaluator Interface
/// @notice Evaluates the health of a loan to determine whether it is sufficiently collateralised and whether it may be
///         liquidated.
/// @dev Implementations must keep health monotonic in the loan's positions: adding collateral or reducing debt never
///      lowers the loan's health, turns a healthy loan unhealthy or turns a non-liquidatable loan liquidatable. A loan
///      reported healthy must never be liquidatable. A loan without borrows must have maximum health,
///      `type(uint256).max`, and be healthy.
interface ILoanEvaluator is IVersioned, IERC165 {
    /// @notice Computes a measure of how well collateralised a loan is.
    /// @dev Implementations should express health with 18 decimals and place the solvency boundary at `1e18`, so that a
    ///      loan at or above it is not liquidatable and one below it is.
    /// @param loan The loan to evaluate.
    /// @return The loan's health; a higher value indicates a better collateralised loan.
    function getLoanHealth(ILendingCore.Loan calldata loan) external view returns (uint256);

    /// @notice Determines whether a loan meets its collateral requirements.
    /// @param loan The loan to evaluate.
    /// @return True if the loan is healthy, false otherwise.
    function isLoanHealthy(ILendingCore.Loan calldata loan) external view returns (bool);

    /// @notice Determines whether a loan may be liquidated, and how unhealthy it is.
    /// @param loan The loan to evaluate.
    /// @return liquidatable True if the loan is liquidatable, false otherwise.
    /// @return health The loan's health, as `getLoanHealth` reports it.
    function isLoanLiquidatable(ILendingCore.Loan calldata loan)
        external
        view
        returns (bool liquidatable, uint256 health);
}
