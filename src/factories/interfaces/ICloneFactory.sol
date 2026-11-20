// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IVersioned} from "../../interfaces/IVersioned.sol";

/// @title  ICloneFactory
/// @notice Common shape shared by every Specific Factory: clones and initializes a single fixed Implementation.
interface ICloneFactory is IVersioned {
    /// @notice Emitted after deploying a clone, before initializing it.
    /// @dev Reverted together with the deployment if initialization fails.
    /// @param  instance Address of the newly cloned instance
    /// @param  salt     CREATE2 salt used to deploy `instance`
    event Cloned(address indexed instance, bytes32 salt);

    /// @notice Clones the Implementation at a deterministic address namespaced to the caller, then initializes it.
    /// @param  salt Caller-chosen CREATE2 salt
    /// @param  data ABI-encoded initialization fields for the clone's Implementation
    /// @return instance Address of the freshly cloned and initialized instance
    function clone(bytes32 salt, bytes calldata data) external returns (address instance);

    /// @notice Implementation contract every clone from this factory delegatecalls to.
    /// @return Implementation address
    function IMPLEMENTATION() external view returns (address);

    /// @notice Predicts the address `caller`'s `clone` would deploy to, without deploying it.
    /// @param  caller Account that would call `clone`
    /// @param  salt Candidate CREATE2 salt
    /// @return predicted Address the clone would be deployed at
    function predictAddress(address caller, bytes32 salt) external view returns (address predicted);
}
