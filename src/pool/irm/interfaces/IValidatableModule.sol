// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../../interfaces/IVersioned.sol";

/// @title Validatable Module Interface
/// @notice Defines configuration validation and metadata shared by external IRM modules.
/// @dev Stateful modules may require empty parameters and keep their configuration in their own storage.
interface IValidatableModule is IERC165, IVersioned {
    /// @notice Returns whether a module configuration is valid.
    /// @dev Implementations should return false for unsupported configurations. Unexpected failures may revert and are
    ///      propagated by callers.
    /// @param params Proposed module-specific parameters.
    /// @return True if the module accepts the configuration.
    function isValid(bytes calldata params) external view returns (bool);
}
