// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title Always Applicable Condition Library
/// @notice Provides a condition that is always satisfied.
library AlwaysApplicableCondition {
    /// @notice Validates always-applicable condition parameters.
    /// @dev `params` must be empty because this condition has no configuration.
    /// @param params Encoded condition parameters.
    /// @return True if `params` is empty.
    function isValid(bytes memory params) internal pure returns (bool) {
        return params.length == 0;
    }

    /// @notice Returns whether the condition applies to an account.
    /// @dev The account input is ignored because this condition is always applicable.
    /// @return True for every account.
    function isApplicable(bytes memory, address) internal pure returns (bool) {
        return true;
    }
}
