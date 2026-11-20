// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IBalanceOf} from "../../../../interfaces/IBalanceOf.sol";

/// @title Token Balance Condition Library
/// @notice Provides a condition that applies when an account holds a minimum token balance.
/// @dev Parameters must be encoded as `abi.encode(address token, uint256 minimumBalance)`.
///
///      The shared `balanceOf(address)` signature means it can, for example, check an ERC-20 or ERC-721 holding to give
///      holders a discount, or read the debt token of the pool using it, whose balance is an account's outstanding
///      debt, to give large borrowers a discount.
///
///      Integrators should weigh two limitations of this condition:
///      1. Whoever can move an account's balance can move the account on or off the IRM: the account itself, or anyone
///         transferring it tokens or repaying its debt and then syncing it. A change that lasts only one transaction,
///         e.g. via a flash loan, keeps the IRM the account qualified for, except on the debt token of the pool using
///         it, which re-syncs an account on every change to its debt.
///      2. An account whose balance moves for good stays on its current IRM until it is next synced.
library TokenBalanceCondition {
    /// @notice Validates token balance condition parameters.
    /// @dev `params` must encode a nonzero minimum balance and a token that successfully returns one ABI-encoded word
    ///      from `balanceOf(address)`.
    /// @param params Encoded token address and minimum balance.
    /// @return True if `params` contains a supported token and a nonzero minimum balance.
    function isValid(bytes memory params) internal view returns (bool) {
        if (params.length != 64) return false;

        (address token, uint256 minimumBalance) = abi.decode(params, (address, uint256));
        if (minimumBalance == 0) return false;

        (bool success, bytes memory returnData) =
            token.staticcall(abi.encodeCall(IBalanceOf.balanceOf, (address(this))));
        return success && returnData.length == 32;
    }

    /// @notice Returns whether an account holds at least the configured minimum token balance.
    /// @dev Reverts from parameter decoding or the token's `balanceOf` call are propagated.
    /// @param params Encoded token address and minimum balance.
    /// @param account Account whose token balance is checked.
    /// @return True if the account's token balance is greater than or equal to the configured minimum.
    function isApplicable(bytes memory params, address account) internal view returns (bool) {
        (address token, uint256 minimumBalance) = abi.decode(params, (address, uint256));
        return IBalanceOf(token).balanceOf(account) >= minimumBalance;
    }
}
