// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title IRM Constants
/// @notice Rate bounds shared by IRM libraries.
library IRMConstants {
    /// @notice Maximum supported borrow rate of 1,000%, scaled to 18dp.
    uint256 internal constant MAX_BORROW_RATE = 10e18;

    /// @notice Maximum supported retention rate of 100%, scaled to 18dp.
    uint256 internal constant MAX_RETENTION_RATE = 1e18;
}
