// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {MathUtils} from "src/lib/MathUtils.sol";

/// @dev Exposes `MathUtils` over an external call so reverts can be asserted with `vm.expectRevert`, which needs a
///      call frame to observe. Value assertions call the library directly.
contract MathUtilsHarness {
    function exponentialBySquaring(uint256 x, uint256 n, uint256 scale) external pure returns (uint256) {
        return MathUtils.exponentialBySquaring(x, n, scale);
    }
}
