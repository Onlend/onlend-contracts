// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IRetentionRateModule} from "../../interfaces/IRetentionRateModule.sol";

/// @title External Retention Rate Library
/// @notice Delegates retention rate validation and calculation to an external retention rate module.
/// @dev Retention rate parameters must be encoded as `abi.encode(address module, bytes externalModuleParams)`. The
///      external module is responsible for validating and interpreting `externalModuleParams`.
library ExternalRetentionRate {
    /// @notice Validates an external retention rate module and its parameters.
    /// @dev Reverts from ABI decoding or the external module are propagated.
    /// @param params Parameters encoded as `abi.encode(address module, bytes externalModuleParams)`.
    /// @return True if the module is supported and accepts its parameters.
    function isValid(bytes memory params) internal view returns (bool) {
        if (params.length < 96) return false;

        (address module, bytes memory externalModuleParams) = abi.decode(params, (address, bytes));
        if (!ERC165Checker.supportsInterface(module, type(IRetentionRateModule).interfaceId)) return false;

        return IRetentionRateModule(module).isValid(externalModuleParams);
    }

    /// @notice Returns the retention rate calculated by an external retention rate module.
    /// @dev `params` is assumed to have previously passed `isValid`. The module response is returned unchanged and is
    ///      capped by the calling IRM. Reverts from ABI decoding or the external module are propagated.
    /// @param params Encoded external retention rate module address and module-specific parameters.
    /// @param idleLiquidity Current idle liquidity in the pool.
    /// @param totalDebt Current total debt in the pool.
    /// @param totalIrmDebt Current total debt using this IRM.
    /// @return Retention rate returned by the external module, scaled to 18dp.
    function retentionRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        internal
        view
        returns (uint256)
    {
        (address module, bytes memory externalModuleParams) = abi.decode(params, (address, bytes));
        return IRetentionRateModule(module).retentionRate(externalModuleParams, idleLiquidity, totalDebt, totalIrmDebt);
    }
}
