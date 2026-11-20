// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IBorrowRateModule} from "../../interfaces/IBorrowRateModule.sol";

/// @title External Borrow Rate Library
/// @notice Delegates borrow rate validation and calculation to an external borrow rate module.
/// @dev Borrow rate parameters must be encoded as `abi.encode(address module, bytes externalModuleParams)`. The
///      external module is responsible for validating and interpreting `externalModuleParams`.
library ExternalBorrowRate {
    /// @notice Validates an external borrow rate module and its parameters.
    /// @dev Reverts from ABI decoding or the external module are propagated.
    /// @param params Parameters encoded as `abi.encode(address module, bytes externalModuleParams)`.
    /// @return True if the module is supported and accepts its parameters.
    function isValid(bytes memory params) internal view returns (bool) {
        if (params.length < 96) return false;

        (address module, bytes memory externalModuleParams) = abi.decode(params, (address, bytes));
        if (!ERC165Checker.supportsInterface(module, type(IBorrowRateModule).interfaceId)) return false;

        return IBorrowRateModule(module).isValid(externalModuleParams);
    }

    /// @notice Returns the borrow rate calculated by an external borrow rate module, updating any state the module
    ///         keeps.
    /// @dev `params` is assumed to have previously passed `isValid`. The module response is returned unchanged and is
    ///      capped by the calling IRM. Reverts from ABI decoding or the external module are propagated.
    /// @param params Encoded external borrow rate module address and module-specific parameters.
    /// @param idleLiquidity Current idle liquidity in the pool.
    /// @param totalDebt Current total debt in the pool.
    /// @param totalIrmDebt Current total debt using this IRM.
    /// @return Borrow rate returned by the external module, scaled to 18dp.
    function borrowRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        internal
        returns (uint256)
    {
        (address module, bytes memory externalModuleParams) = abi.decode(params, (address, bytes));
        return IBorrowRateModule(module).borrowRate(externalModuleParams, idleLiquidity, totalDebt, totalIrmDebt);
    }

    /// @notice Returns the borrow rate `borrowRate` would return, without updating state.
    /// @dev `params` is assumed to have previously passed `isValid`. The module response is returned unchanged and is
    ///      capped by the calling IRM. Reverts from ABI decoding or the external module are propagated.
    /// @param params Encoded external borrow rate module address and module-specific parameters.
    /// @param idleLiquidity Current idle liquidity in the pool.
    /// @param totalDebt Current total debt in the pool.
    /// @param totalIrmDebt Current total debt using this IRM.
    /// @return Borrow rate previewed by the external module, scaled to 18dp.
    function previewBorrowRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        internal
        view
        returns (uint256)
    {
        (address module, bytes memory externalModuleParams) = abi.decode(params, (address, bytes));
        return IBorrowRateModule(module).previewBorrowRate(externalModuleParams, idleLiquidity, totalDebt, totalIrmDebt);
    }
}
