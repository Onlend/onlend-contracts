// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IValidatableModule} from "./IValidatableModule.sol";

/// @title Retention Rate Module Interface
/// @notice Defines an external module that computes the share of accrued interest retained by the protocol.
/// @dev Implementations may derive the retention rate from module-specific parameters, pool state, their own storage,
///      or external state.
interface IRetentionRateModule is IValidatableModule {
    /// @notice Returns the retention rate for a module configuration and pool state.
    /// @dev `params` must have previously been accepted by `isValid`. Implementation reverts are propagated by callers.
    /// @param params Module-specific retention rate parameters.
    /// @param idleLiquidity Current idle liquidity in the pool.
    /// @param totalDebt Current total debt in the pool.
    /// @param totalIrmDebt Current total debt using this IRM.
    /// @return Retention rate, scaled to 18dp.
    function retentionRate(bytes calldata params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        view
        returns (uint256);
}
