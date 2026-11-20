// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Math Utils
/// @notice Common constants and formulas used in math calculations.
library MathUtils {
    using Math for uint256;

    /// @notice Seconds in a year; leap years are not accounted for.
    uint256 internal constant SECONDS_IN_YEAR = 365 days;

    /// @notice One, scaled to 4 decimal places.
    uint256 internal constant ONE_4_DP = 1e4;

    /// @notice One, scaled to 18 decimal places.
    uint256 internal constant ONE_18_DP = 1e18;

    /// @notice Raises a fixed-point base to an unscaled integer power.
    /// @dev Computes `scale * (x / scale) ** n` by binary exponentiation, in `O(log n)` fixed-point multiplications.
    ///      Reverts with an arithmetic panic if an intermediate power exceeds `uint256`. Assumes `scale` is non-zero,
    ///      which callers uphold by passing a fixed-point scale constant; the result is undefined otherwise.
    /// @param x Base, scaled by `scale`.
    /// @param n Exponent, unscaled.
    /// @param scale Fixed-point scale shared by `x` and the return value, e.g. `ONE_18_DP`.
    /// @return z `x` raised to the power of `n`, scaled by `scale` and rounded down.
    function exponentialBySquaring(uint256 x, uint256 n, uint256 scale) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? x : scale;
        for (n /= 2; n != 0; n /= 2) {
            x = x.mulDiv(x, scale);
            if (n % 2 != 0) {
                z = z.mulDiv(x, scale);
            }
        }
    }
}
