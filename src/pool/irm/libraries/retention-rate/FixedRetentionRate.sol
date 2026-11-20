// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IRMConstants} from "../IRMConstants.sol";

/// @title Fixed Retention Rate Library
/// @notice Computes a retention rate that is fixed by configuration.
library FixedRetentionRate {
    /// @notice Validates fixed retention rate parameters.
    /// @dev `params` must be `abi.encode(uint256 retentionRate_)`.
    /// @param params Encoded fixed retention rate.
    /// @return True if the encoded retention rate is less than or equal to `IRMConstants.MAX_RETENTION_RATE`.
    function isValid(bytes memory params) internal pure returns (bool) {
        if (params.length != 32) return false;

        uint256 retentionRate_ = abi.decode(params, (uint256));
        return retentionRate_ <= IRMConstants.MAX_RETENTION_RATE;
    }

    /// @notice Returns the configured fixed retention rate.
    /// @dev Liquidity and debt inputs are ignored because the retention rate is fixed.
    /// @param params Encoded fixed retention rate.
    /// @return Fixed retention rate.
    function retentionRate(bytes memory params, uint256, uint256, uint256) internal pure returns (uint256) {
        return abi.decode(params, (uint256));
    }
}
