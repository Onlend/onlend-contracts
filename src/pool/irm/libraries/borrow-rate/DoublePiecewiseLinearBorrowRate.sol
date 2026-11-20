// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MathUtils} from "../../../../lib/MathUtils.sol";
import {InterestMath} from "../../../lib/InterestMath.sol";
import {IRMConstants} from "../IRMConstants.sol";

/// @title Double Piecewise Linear Borrow Rate Library
/// @notice Computes a borrow rate from pool utilisation using three linear slopes separated by two utilisation points.
library DoublePiecewiseLinearBorrowRate {
    /// @notice Validates double piecewise linear borrow rate parameters.
    /// @dev `params` must be `abi.encode(uint256 baseRate, uint256 utilisation1, uint256 utilisation2, uint256 slope1,
    ///      uint256 slope2, uint256 slope3)`. Reverts from arithmetic overflow are propagated.
    /// @param params Encoded base rate, utilisation points, and slopes, all scaled to 18dp.
    /// @return True if the utilisation points and maximum configured borrow rate are within the supported ranges.
    function isValid(bytes memory params) internal pure returns (bool) {
        if (params.length != 192) return false;

        (uint256 baseRate, uint256 utilisation1, uint256 utilisation2, uint256 slope1, uint256 slope2, uint256 slope3) =
            abi.decode(params, (uint256, uint256, uint256, uint256, uint256, uint256));

        return utilisation1 > 0 && utilisation1 < utilisation2 && utilisation2 < MathUtils.ONE_18_DP
            && baseRate + slope1 + slope2 + slope3 <= IRMConstants.MAX_BORROW_RATE;
    }

    /// @notice Returns the double piecewise linear borrow rate for the current pool utilisation.
    /// @dev `params` must use the encoding documented in `isValid`. Total IRM debt is ignored because this model
    ///      depends only on pool utilisation.
    /// @param params Encoded base rate, utilisation points, and slopes, all scaled to 18dp.
    /// @param idleLiquidity Current idle liquidity.
    /// @param totalDebt Current total debt.
    /// @return Borrow rate, scaled to 18dp.
    function borrowRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256)
        internal
        pure
        returns (uint256)
    {
        (uint256 baseRate, uint256 utilisation1, uint256 utilisation2, uint256 slope1, uint256 slope2, uint256 slope3) =
            abi.decode(params, (uint256, uint256, uint256, uint256, uint256, uint256));

        uint256 utilisation = InterestMath.calcUtilisation(idleLiquidity, totalDebt);

        if (utilisation <= utilisation1) {
            return baseRate + Math.mulDiv(utilisation, slope1, utilisation1);
        }

        if (utilisation <= utilisation2) {
            uint256 excessUtilisation = utilisation - utilisation1;
            uint256 excessUtilisationRange = utilisation2 - utilisation1;

            return baseRate + slope1 + Math.mulDiv(excessUtilisation, slope2, excessUtilisationRange);
        }

        uint256 finalExcessUtilisation = utilisation - utilisation2;
        uint256 finalExcessUtilisationRange = MathUtils.ONE_18_DP - utilisation2;

        return baseRate + slope1 + slope2 + Math.mulDiv(finalExcessUtilisation, slope3, finalExcessUtilisationRange);
    }
}
