// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../../interfaces/IVersioned.sol";

/// @title Interest Rate Model Interface
/// @notice Defines borrow rate, retention rate, and applicability hooks for pool IRMs.
/// @dev Implementations are responsible for enforcing any rate bounds. Consumers trust an IRM and generally do not cap
///      returned values themselves.
interface IIRM is IERC165, IVersioned {
    /// @notice Returns the borrow rate for the given pool state, updating any state the IRM keeps.
    /// @dev Implementations may restrict which caller can update their state, and must not make state-changing calls
    ///      into the pool whose state they are given.
    /// @param idleLiquidity Current idle liquidity.
    /// @param totalDebt Current total debt.
    /// @param totalIrmDebt Current total debt using this IRM.
    /// @return Borrow rate, scaled to 18dp.
    function borrowRate(uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt) external returns (uint256);

    /// @notice Returns the borrow rate `borrowRate` would return for the given pool state, without updating state.
    /// @param idleLiquidity Current idle liquidity.
    /// @param totalDebt Current total debt.
    /// @param totalIrmDebt Current total debt using this IRM.
    /// @return Borrow rate, scaled to 18dp.
    function previewBorrowRate(uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        view
        returns (uint256);

    /// @notice Returns the retention rate for the given pool state.
    /// @param idleLiquidity Current idle liquidity.
    /// @param totalDebt Current total debt.
    /// @param totalIrmDebt Current total debt using this IRM.
    /// @return Retention rate, scaled to 18dp.
    function retentionRate(uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        view
        returns (uint256);

    /// @notice Returns whether this IRM applies to a user.
    /// @param user User checked against the IRM condition.
    /// @return True if this IRM applies to `user`.
    function isApplicable(address user) external view returns (bool);
}
