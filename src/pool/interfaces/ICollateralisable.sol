// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title  Collateralisable Interface
/// @notice Pool that can hold positions backing a loan.
interface ICollateralisable {
    /// @notice Returns the collateral token representing positions held by this pool.
    /// @return Collateral token address.
    function collateralToken() external view returns (address);
}
