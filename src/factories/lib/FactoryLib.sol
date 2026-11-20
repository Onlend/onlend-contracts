// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title  FactoryLib
/// @notice Shared helpers for the Factories domain.
library FactoryLib {
    /// @notice Namespaces `salt` to `caller`, so two callers supplying the same salt never collide.
    /// @param  caller Account the salt is namespaced to
    /// @param  salt Caller-chosen salt
    /// @return Namespaced salt
    function callerSalt(address caller, bytes32 salt) internal pure returns (bytes32) {
        return keccak256(abi.encode(caller, salt));
    }
}
