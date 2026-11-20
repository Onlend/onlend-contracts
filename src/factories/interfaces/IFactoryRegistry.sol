// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IVersioned} from "../../interfaces/IVersioned.sol";

/// @title  IFactoryRegistry
/// @notice Common shape shared by every Factory Registry: an allow-list of Clone Factories that deploys can be routed
///         through.
interface IFactoryRegistry is IVersioned {
    /// @notice Returns whether `cloneFactory` is registered.
    /// @param  cloneFactory Clone Factory address to check
    /// @return registered True if `cloneFactory` is registered
    function isCloneFactory(address cloneFactory) external view returns (bool registered);

    /// @notice Returns every registered Clone Factory.
    /// @return list Registered Clone Factory addresses
    function cloneFactories() external view returns (address[] memory list);

    /// @notice Returns how many Clone Factories are registered.
    /// @return length Number of registered Clone Factories
    function cloneFactoriesLength() external view returns (uint256 length);

    /// @notice Returns the registered Clone Factory at `index`.
    /// @param  index Index into the registered Clone Factories
    /// @return cloneFactory Clone Factory address at `index`
    function cloneFactoryAt(uint256 index) external view returns (address cloneFactory);

    /// @notice Predicts the address a deploy through `cloneFactory` with `salt` would produce for `caller`, without
    ///         deploying it.
    /// @param  cloneFactory Registered Clone Factory address to deploy through
    /// @param  caller Account that would make the deploy
    /// @param  salt Candidate salt
    /// @return predicted Address the clone would be deployed at
    function predictAddress(address cloneFactory, address caller, bytes32 salt)
        external
        view
        returns (address predicted);
}
