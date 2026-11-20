// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title Ordered Address Array
/// @notice Helpers for a storage array of addresses where callers control the exact position of each element (e.g.
///         priority-based insertion), unlike `EnumerableSet` which offers no positional control and no order guarantees
///         on removal (it swap-and-pops). Insert/remove are O(n) due to shifting; intended for small, bounded arrays
///         (tens of elements), not large sets.
library OrderedAddressArray {
    /// @notice Inserts `value` at `index`, shifting elements at `index` and after one position to the right.
    /// @dev `index == self.length` appends. Reverts with the array's default out-of-bounds panic if
    ///      `index > self.length`.
    function insertAt(address[] storage self, address value, uint256 index) internal {
        self.push();
        for (uint256 i = self.length - 1; i > index; i--) {
            self[i] = self[i - 1];
        }
        self[index] = value;
    }

    /// @notice Removes the element at `index`, shifting subsequent elements one position to the left.
    /// @dev Reverts with the array's default out-of-bounds panic if `index >= self.length`.
    /// @return removed The removed value.
    function removeAt(address[] storage self, uint256 index) internal returns (address removed) {
        uint256 length = self.length;
        removed = self[index];

        for (uint256 i = index; i < length - 1; i++) {
            self[i] = self[i + 1];
        }
        self.pop();
    }

    /// @notice Finds the first occurrence of `value`.
    /// @return found True if `value` is present.
    /// @return index Index of `value` if `found`, otherwise 0.
    function indexOf(address[] storage self, address value) internal view returns (bool found, uint256 index) {
        uint256 length = self.length;
        for (uint256 i; i < length; i++) {
            if (self[i] == value) return (true, i);
        }
        return (false, 0);
    }
}
