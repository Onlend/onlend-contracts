// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MathUtils} from "../../../../lib/MathUtils.sol";
import {InterestMath} from "../../../lib/InterestMath.sol";
import {IRMConstants} from "../IRMConstants.sol";

/// @title Linear Borrow Rate Library
/// @notice Computes a borrow rate from pool utilisation using a single linear slope.
library LinearBorrowRate {
    /// @notice Validates linear borrow rate parameters.
    /// @dev `params` must be `abi.encode(uint256 baseRate, uint256 slope)`. Reverts from arithmetic overflow are
    ///      propagated.
    /// @param params Encoded base rate and slope, both scaled to 18dp.
    /// @return True if the maximum configured borrow rate is within the supported range.
    function isValid(bytes memory params) internal pure returns (bool) {
        if (params.length != 64) return false;

        (uint256 baseRate, uint256 slope) = abi.decode(params, (uint256, uint256));
        return baseRate + slope <= IRMConstants.MAX_BORROW_RATE;
    }

    /// @notice Returns the linear borrow rate for the current pool utilisation.
    /// @dev `params` must use the encoding documented in `isValid`. Total IRM debt is ignored because this model
    ///      depends only on pool utilisation.
    /// @param params Encoded base rate and slope, both scaled to 18dp.
    /// @param idleLiquidity Current idle liquidity.
    /// @param totalDebt Current total debt.
    /// @return Borrow rate, scaled to 18dp.
    function borrowRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256)
        internal
        pure
        returns (uint256)
    {
        (uint256 baseRate, uint256 slope) = abi.decode(params, (uint256, uint256));

        uint256 utilisation = InterestMath.calcUtilisation(idleLiquidity, totalDebt);

        return baseRate + Math.mulDiv(utilisation, slope, MathUtils.ONE_18_DP);
    }
}
