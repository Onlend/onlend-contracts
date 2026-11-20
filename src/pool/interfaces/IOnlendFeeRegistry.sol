// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";

/// @title  IOnlendFeeRegistry
/// @notice Source of the fee Onlend takes from the interest each pool accrues, and of the account it is paid to.
interface IOnlendFeeRegistry is IERC165, IVersioned {
    /// @notice Returns the fee configuration that applies to a pool.
    /// @param  pool Pool to resolve the configuration for.
    /// @return fixedFeeBps Share of all accrued interest taken by Onlend on top of the pool's retention, in bps, at
    ///         most 10_000.
    /// @return splitFeeBps Share of the pool's retained interest taken by Onlend, in bps, at most 10_000.
    function feeConfig(address pool) external view returns (uint16 fixedFeeBps, uint16 splitFeeBps);

    /// @notice Returns the account Onlend's fee shares are minted to.
    /// @return Fee recipient address, never zero.
    function feeRecipient() external view returns (address);
}
