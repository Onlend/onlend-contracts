// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILendingCore} from "../lending-core/interfaces/ILendingCore.sol";
import {IPool} from "../pool/interfaces/IPool.sol";

/// @title LoanPositionLib
/// @notice Lookups over, and in-place shaping of, an array of loan positions.
library LoanPositionLib {
    /// @notice Shortens `positions` to its first `length` entries.
    /// @dev Modifies the array in place, so any other reference to it sees the shortened result. `length` is clamped to
    ///      the array's current length, since growing it would reach past the memory it owns.
    /// @param positions The positions to shorten.
    /// @param length The number of entries to keep.
    /// @return The same array, holding at most `length` entries.
    function truncate(ILendingCore.LoanPosition[] memory positions, uint256 length)
        internal
        pure
        returns (ILendingCore.LoanPosition[] memory)
    {
        length = Math.min(length, positions.length);

        // Only ever shrinks the array, so it writes nothing outside the memory the array already owns.
        assembly ("memory-safe") {
            mstore(positions, length)
        }

        return positions;
    }

    /// @notice Finds the position held in `pool`.
    /// @dev Returns the first match; where `positions` holds more than one entry in the same pool, the later entries
    ///      are unreachable through this function.
    /// @param positions The positions to search.
    /// @param pool The pool to look for.
    /// @return found True if a position in `pool` is present.
    /// @return index The index of that position; meaningless when `found` is false.
    function findPosition(ILendingCore.LoanPosition[] calldata positions, IPool pool)
        internal
        pure
        returns (bool found, uint256 index)
    {
        for (uint256 i; i < positions.length; ++i) {
            if (address(positions[i].pool) == address(pool)) return (true, i);
        }
        return (false, 0);
    }

    /// @notice Whether any pool is named by more than one position.
    /// @dev The scan is O(n²), so it suits the short arrays a loan produces rather than unbounded input.
    /// @param positions The positions to scan.
    /// @return True if some pool appears more than once.
    function hasDuplicatePool(ILendingCore.LoanPosition[] calldata positions) internal pure returns (bool) {
        for (uint256 i = 1; i < positions.length; ++i) {
            for (uint256 j; j < i; ++j) {
                if (address(positions[j].pool) == address(positions[i].pool)) return true;
            }
        }
        return false;
    }
}
