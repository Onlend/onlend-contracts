// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {ICloneFactory} from "../interfaces/ICloneFactory.sol";
import {FactoryLib} from "../lib/FactoryLib.sol";

/// @title  CloneFactory
/// @notice Base for a Specific Factory: holds one fixed Implementation, clones it deterministically, and dispatches
///         initialization of the clone.
/// @dev    Permissionless and non-upgradeable — `IMPLEMENTATION` never changes, so every clone delegatecalls the same
///         logic forever.
abstract contract CloneFactory is ICloneFactory {
    /// @inheritdoc ICloneFactory
    address public immutable IMPLEMENTATION;

    /// @notice Thrown when the constructor is given an `implementation` with no code.
    error ImplementationNotContract();

    /// @param implementation Implementation contract every clone from this factory delegatecalls to
    constructor(address implementation) {
        if (implementation.code.length == 0) revert ImplementationNotContract();
        IMPLEMENTATION = implementation;
    }

    /// @inheritdoc ICloneFactory
    function clone(bytes32 salt, bytes calldata data) external override(ICloneFactory) returns (address instance) {
        instance = Clones.cloneDeterministic(IMPLEMENTATION, FactoryLib.callerSalt(msg.sender, salt));
        emit Cloned(instance, salt);
        _initialize(instance, data);
    }

    /// @inheritdoc ICloneFactory
    function predictAddress(address caller, bytes32 salt)
        external
        view
        override(ICloneFactory)
        returns (address predicted)
    {
        return Clones.predictDeterministicAddress(IMPLEMENTATION, FactoryLib.callerSalt(caller, salt), address(this));
    }

    /// @notice Decodes `data` and initializes `instance`'s Implementation.
    /// @dev    Concrete factories implement this; the encoded shape differs per Implementation.
    /// @param  instance Clone to initialize
    /// @param  data ABI-encoded initialization fields for `instance`'s Implementation
    function _initialize(address instance, bytes calldata data) internal virtual;
}
