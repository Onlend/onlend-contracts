// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title Token Balance Interface
/// @notice Minimal interface for querying an account's token balance.
/// @dev ERC-20 and ERC-721 tokens share this `balanceOf(address)` signature.
interface IBalanceOf {
    /// @notice Returns the token balance of an account.
    /// @param account Account whose balance is queried.
    /// @return Balance held by `account`.
    function balanceOf(address account) external view returns (uint256);
}
