// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IRMConstants} from "../IRMConstants.sol";

/// @title Fixed Borrow Rate Library
/// @notice Computes a borrow rate that is fixed by configuration.
library FixedBorrowRate {
    /// @notice Validates fixed borrow rate parameters.
    /// @dev `params` must be `abi.encode(uint256 borrowRate_)`.
    /// @param params Encoded fixed borrow rate, scaled to 18dp.
    /// @return True if the encoded borrow rate is within the supported range.
    function isValid(bytes memory params) internal pure returns (bool) {
        if (params.length != 32) return false;

        uint256 borrowRate_ = abi.decode(params, (uint256));
        return borrowRate_ <= IRMConstants.MAX_BORROW_RATE;
    }

    /// @notice Returns the configured fixed borrow rate.
    /// @dev Liquidity and debt inputs are ignored because the borrow rate is fixed.
    /// @param params Encoded fixed borrow rate, scaled to 18dp.
    /// @return Fixed borrow rate, scaled to 18dp.
    function borrowRate(bytes memory params, uint256, uint256, uint256) internal pure returns (uint256) {
        return abi.decode(params, (uint256));
    }
}
