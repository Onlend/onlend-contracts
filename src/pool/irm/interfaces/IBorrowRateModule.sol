// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IValidatableModule} from "./IValidatableModule.sol";

/// @title Borrow Rate Module Interface
/// @notice Defines an external module that computes the borrow rate for an IRM.
/// @dev Implementations may derive the borrow rate from module-specific parameters, pool state, their own storage, or
///      external state.
interface IBorrowRateModule is IValidatableModule {
    /// @notice Returns the borrow rate for a module configuration and pool state, updating any state the module keeps.
    /// @dev `params` must have previously been accepted by `isValid`. Implementation reverts are propagated by callers.
    ///      Implementations may restrict which caller can update their state, and must not make state-changing calls
    ///      into the pool whose state they are given.
    /// @param params Module-specific borrow rate parameters.
    /// @param idleLiquidity Current idle liquidity in the pool.
    /// @param totalDebt Current total debt in the pool.
    /// @param totalIrmDebt Current total debt using this IRM.
    /// @return Borrow rate, scaled to 18dp.
    function borrowRate(bytes calldata params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        returns (uint256);

    /// @notice Returns the borrow rate `borrowRate` would return for a module configuration and pool state, without
    ///         updating state.
    /// @dev `params` must have previously been accepted by `isValid`. Implementation reverts are propagated by callers.
    /// @param params Module-specific borrow rate parameters.
    /// @param idleLiquidity Current idle liquidity in the pool.
    /// @param totalDebt Current total debt in the pool.
    /// @param totalIrmDebt Current total debt using this IRM.
    /// @return Borrow rate, scaled to 18dp.
    function previewBorrowRate(bytes calldata params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        view
        returns (uint256);
}
