// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IConditionModule} from "../../interfaces/IConditionModule.sol";

/// @title External Condition Library
/// @notice Delegates IRM applicability checks to an external condition module.
/// @dev Condition parameters must be encoded as `abi.encode(address module, bytes externalModuleParams)`. The external
///      module is responsible for validating and interpreting `externalModuleParams`.
library ExternalCondition {
    /// @notice Validates an external condition module and its parameters.
    /// @dev Reverts from ABI decoding or the external module are propagated.
    /// @param params Parameters encoded as `abi.encode(address module, bytes externalModuleParams)`.
    /// @return True if the module is supported and accepts its parameters.
    function isValid(bytes memory params) internal view returns (bool) {
        if (params.length < 96) return false;

        (address module, bytes memory externalModuleParams) = abi.decode(params, (address, bytes));
        if (!ERC165Checker.supportsInterface(module, type(IConditionModule).interfaceId)) return false;

        return IConditionModule(module).isValid(externalModuleParams);
    }

    /// @notice Returns whether an external condition module applies to an account.
    /// @dev `params` is assumed to have previously passed `isValid`. Reverts from ABI decoding or the external module
    ///      are propagated.
    /// @param params Encoded external condition module address and module-specific parameters.
    /// @param account Account whose applicability is checked.
    /// @return True if the external condition module applies to `account`.
    function isApplicable(bytes memory params, address account) internal view returns (bool) {
        (address module, bytes memory externalModuleParams) = abi.decode(params, (address, bytes));
        return IConditionModule(module).isApplicable(externalModuleParams, account);
    }
}
