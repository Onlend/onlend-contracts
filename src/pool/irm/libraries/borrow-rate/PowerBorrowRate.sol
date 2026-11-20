// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MathUtils} from "../../../../lib/MathUtils.sol";
import {InterestMath} from "../../../lib/InterestMath.sol";
import {IRMConstants} from "../IRMConstants.sol";

/// @title Power Borrow Rate Library
/// @notice Computes a borrow rate from pool utilisation using a configurable power curve.
/// @dev The curve is `baseRate + slope * utilisation ** exponent`, with rates and utilisation scaled to 18dp.
library PowerBorrowRate {
    /// @notice Maximum supported exponent for the utilisation power curve.
    /// @dev Capped at 10 to support strongly convex curves while avoiding excessively sharp configurations that
    ///      contribute little below high utilisation and increase computation.
    uint256 internal constant MAX_EXPONENT = 10;

    /// @notice Validates power borrow rate parameters.
    /// @dev `params` must be `abi.encode(uint256 baseRate, uint256 slope, uint256 exponent)`. Reverts from arithmetic
    ///      overflow are propagated.
    /// @param params Encoded base rate and slope, both scaled to 18dp, and an unscaled integer exponent.
    /// @return True if the exponent and maximum configured borrow rate are within the supported ranges.
    function isValid(bytes memory params) internal pure returns (bool) {
        if (params.length != 96) return false;

        (uint256 baseRate, uint256 slope, uint256 exponent) = abi.decode(params, (uint256, uint256, uint256));
        return exponent > 1 && exponent <= MAX_EXPONENT && baseRate + slope <= IRMConstants.MAX_BORROW_RATE;
    }

    /// @notice Returns the power borrow rate for the current pool utilisation.
    /// @dev `params` must use the encoding documented in `isValid`. Fixed-point operations round down, including
    ///      intermediate operations performed during exponentiation. Total IRM debt is ignored because this model
    ///      depends only on pool utilisation.
    /// @param params Encoded base rate and slope, both scaled to 18dp, and an unscaled integer exponent.
    /// @param idleLiquidity Current idle liquidity.
    /// @param totalDebt Current total debt.
    /// @return Borrow rate, scaled to 18dp.
    function borrowRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256)
        internal
        pure
        returns (uint256)
    {
        (uint256 baseRate, uint256 slope, uint256 exponent) = abi.decode(params, (uint256, uint256, uint256));

        uint256 utilisation = InterestMath.calcUtilisation(idleLiquidity, totalDebt);
        uint256 poweredUtilisation = MathUtils.exponentialBySquaring(utilisation, exponent, MathUtils.ONE_18_DP);

        return baseRate + Math.mulDiv(slope, poweredUtilisation, MathUtils.ONE_18_DP);
    }
}
