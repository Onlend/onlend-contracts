// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IValidatableModule} from "./IValidatableModule.sol";

/// @title Condition Module Interface
/// @notice Defines an external module that determines whether an IRM applies to an account.
/// @dev Implementations may derive applicability from module-specific parameters, their own storage, or external state.
interface IConditionModule is IValidatableModule {
    /// @notice Returns whether the condition applies to an account.
    /// @dev `params` must have previously been accepted by `isValid`. Implementation reverts are propagated by callers.
    /// @param params Module-specific condition parameters.
    /// @param account Account whose applicability is checked.
    /// @return True if the IRM condition applies to `account`.
    function isApplicable(bytes calldata params, address account) external view returns (bool);
}
