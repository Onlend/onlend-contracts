// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ICloneFactory} from "../interfaces/ICloneFactory.sol";
import {IFactoryRegistry} from "../interfaces/IFactoryRegistry.sol";
import {FactoryLib} from "../lib/FactoryLib.sol";

/// @title  FactoryRegistry
/// @notice Base for a Factory Registry: an owner-curated allow-list of Clone Factories that `_clone`/`predictAddress`
///         may be routed through.
/// @dev    Owner-gated wiring since registering/removing a Clone Factory is a privileged action. `_clone` is left to
///         the inheriting contract to expose.
abstract contract FactoryRegistry is IFactoryRegistry, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _cloneFactories;

    /// @notice Emitted when a Clone Factory is registered.
    /// @param  cloneFactory Newly registered Clone Factory address
    event CloneFactoryRegistered(address indexed cloneFactory);

    /// @notice Emitted when a Clone Factory is removed from the registry.
    /// @param  cloneFactory Removed Clone Factory address
    event CloneFactoryRemoved(address indexed cloneFactory);

    /// @notice Thrown when `registerCloneFactory` is given an address with no code.
    error CloneFactoryNotContract();

    /// @notice Thrown when a Clone Factory is not registered.
    /// @param  cloneFactory Unregistered Clone Factory address
    error CloneFactoryNotRegistered(address cloneFactory);

    /// @notice Thrown when a Clone Factory is already registered.
    /// @param  cloneFactory Already-registered Clone Factory address
    error CloneFactoryAlreadyRegistered(address cloneFactory);

    /// @param  owner_ Initial owner, authorised to register/remove Clone Factories
    constructor(address owner_) Ownable(owner_) {}

    /// @notice Registers a Clone Factory, allowing it to be routed through by `_clone`/`predictAddress`.
    /// @dev    Reverts if `cloneFactory` has no code, or is already registered.
    /// @param  cloneFactory_ Clone Factory address to register
    function registerCloneFactory(address cloneFactory_) external onlyOwner {
        if (cloneFactory_.code.length == 0) revert CloneFactoryNotContract();
        if (!_cloneFactories.add(cloneFactory_)) revert CloneFactoryAlreadyRegistered(cloneFactory_);
        emit CloneFactoryRegistered(cloneFactory_);
    }

    /// @notice Removes a Clone Factory from the registry, freeing it for re-registration.
    /// @dev    Reverts if `cloneFactory` is not registered.
    /// @param  cloneFactory_ Clone Factory address to remove
    function removeCloneFactory(address cloneFactory_) external onlyOwner {
        if (!_cloneFactories.remove(cloneFactory_)) revert CloneFactoryNotRegistered(cloneFactory_);
        emit CloneFactoryRemoved(cloneFactory_);
    }

    /// @inheritdoc IFactoryRegistry
    function isCloneFactory(address cloneFactory_) external view override(IFactoryRegistry) returns (bool registered) {
        return _cloneFactories.contains(cloneFactory_);
    }

    /// @inheritdoc IFactoryRegistry
    /// @dev No ordering is guaranteed once a Clone Factory has been removed — removal swaps the last entry into its
    ///      slot.
    function cloneFactories() external view override(IFactoryRegistry) returns (address[] memory list) {
        return _cloneFactories.values();
    }

    /// @inheritdoc IFactoryRegistry
    function cloneFactoriesLength() external view override(IFactoryRegistry) returns (uint256 length) {
        return _cloneFactories.length();
    }

    /// @inheritdoc IFactoryRegistry
    /// @dev No ordering is guaranteed once a Clone Factory has been removed — removal swaps the last entry into its
    ///      slot.
    function cloneFactoryAt(uint256 index) external view override(IFactoryRegistry) returns (address cloneFactory) {
        return _cloneFactories.at(index);
    }

    /// @inheritdoc IFactoryRegistry
    function predictAddress(address cloneFactory_, address caller, bytes32 salt)
        external
        view
        override(IFactoryRegistry)
        returns (address predicted)
    {
        _requireCloneFactoryRegistered(cloneFactory_);
        return ICloneFactory(cloneFactory_).predictAddress(address(this), FactoryLib.callerSalt(caller, salt));
    }

    /// @notice Deploys a new instance through `cloneFactory_`, binding `salt` to the caller.
    /// @param  cloneFactory_ Registered Clone Factory address to deploy through
    /// @param  salt Caller-chosen salt
    /// @param  data ABI-encoded initialization fields for the new instance
    /// @return instance Address of the freshly deployed instance
    function _clone(address cloneFactory_, bytes32 salt, bytes calldata data) internal returns (address instance) {
        _requireCloneFactoryRegistered(cloneFactory_);
        return ICloneFactory(cloneFactory_).clone(FactoryLib.callerSalt(msg.sender, salt), data);
    }

    /// @notice Reverts unless `cloneFactory` is registered.
    /// @param  cloneFactory_ Clone Factory address to check
    function _requireCloneFactoryRegistered(address cloneFactory_) internal view {
        if (!_cloneFactories.contains(cloneFactory_)) revert CloneFactoryNotRegistered(cloneFactory_);
    }
}
