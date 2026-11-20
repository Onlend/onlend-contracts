// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title Versioned Contract Interface
/// @notice Exposes human-readable contract metadata.
interface IVersioned {
    /// @notice Returns the contract name.
    /// @return name_ Human-readable contract name.
    function contractName() external pure returns (string memory name_);

    /// @notice Returns the contract version.
    /// @return version_ Semantic contract version.
    function contractVersion() external pure returns (string memory version_);
}
