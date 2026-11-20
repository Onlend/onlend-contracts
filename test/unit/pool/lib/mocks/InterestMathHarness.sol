// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {InterestMath} from "src/pool/lib/InterestMath.sol";

/// @dev Exposes `InterestMath` over an external call so reverts can be asserted with `vm.expectRevert`, which needs a
///      call frame to observe. Value assertions call the library directly.
contract InterestMathHarness {
    function calcUtilisation(uint256 idleLiquidity, uint256 totalDebt) external pure returns (uint256) {
        return InterestMath.calcUtilisation(idleLiquidity, totalDebt);
    }
}
