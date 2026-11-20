// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MathUtils} from "../../../../lib/MathUtils.sol";
import {InterestMath} from "../../../lib/InterestMath.sol";
import {IRMConstants} from "../IRMConstants.sol";

/// @title Piecewise Linear Borrow Rate Library
/// @notice Computes a borrow rate from pool utilisation using two linear slopes separated by an optimal utilisation.
library PiecewiseLinearBorrowRate {
    /// @notice Validates piecewise linear borrow rate parameters.
    /// @dev `params` must be
    ///      `abi.encode(uint256 baseRate, uint256 optimalUtilisation, uint256 slope1, uint256 slope2)`. Reverts from
    ///      arithmetic overflow are propagated.
    /// @param params Encoded base rate, optimal utilisation, and slopes, all scaled to 18dp.
    /// @return True if the optimal utilisation and maximum configured borrow rate are within the supported ranges.
    function isValid(bytes memory params) internal pure returns (bool) {
        if (params.length != 128) return false;

        (uint256 baseRate, uint256 optimalUtilisation, uint256 slope1, uint256 slope2) =
            abi.decode(params, (uint256, uint256, uint256, uint256));

        return optimalUtilisation > 0 && optimalUtilisation < MathUtils.ONE_18_DP
            && baseRate + slope1 + slope2 <= IRMConstants.MAX_BORROW_RATE;
    }

    /// @notice Returns the piecewise linear borrow rate for the current pool utilisation.
    /// @dev `params` must use the encoding documented in `isValid`. Total IRM debt is ignored because this model
    ///      depends only on pool utilisation.
    /// @param params Encoded base rate, optimal utilisation, and slopes, all scaled to 18dp.
    /// @param idleLiquidity Current idle liquidity.
    /// @param totalDebt Current total debt.
    /// @return Borrow rate, scaled to 18dp.
    function borrowRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256)
        internal
        pure
        returns (uint256)
    {
        (uint256 baseRate, uint256 optimalUtilisation, uint256 slope1, uint256 slope2) =
            abi.decode(params, (uint256, uint256, uint256, uint256));

        uint256 utilisation = InterestMath.calcUtilisation(idleLiquidity, totalDebt);

        if (utilisation <= optimalUtilisation) {
            return baseRate + Math.mulDiv(utilisation, slope1, optimalUtilisation);
        }

        uint256 excessUtilisation = utilisation - optimalUtilisation;
        uint256 excessUtilisationRange = MathUtils.ONE_18_DP - optimalUtilisation;

        return baseRate + slope1 + Math.mulDiv(excessUtilisation, slope2, excessUtilisationRange);
    }
}
