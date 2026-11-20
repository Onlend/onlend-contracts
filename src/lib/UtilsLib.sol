// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

library UtilsLib {
    /// @notice Returns whether exactly one of two amounts is zero.
    /// @param  x First amount.
    /// @param  y Second amount.
    /// @return True when one amount is zero and the other is not.
    function exactlyOneZero(uint256 x, uint256 y) internal pure returns (bool) {
        return (x == 0) != (y == 0);
    }
}
