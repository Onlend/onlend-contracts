// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {LoanPositionLib} from "src/lib/LoanPositionLib.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";

/// @dev Exposes `LoanPositionLib` externally so its calldata arrays can be passed from a test.
contract LoanPositionLibHarness {
    using LoanPositionLib for ILendingCore.LoanPosition[];

    function findPosition(ILendingCore.LoanPosition[] calldata positions, IPool pool)
        external
        pure
        returns (bool found, uint256 index)
    {
        return positions.findPosition(pool);
    }

    function hasDuplicatePool(ILendingCore.LoanPosition[] calldata positions) external pure returns (bool) {
        return positions.hasDuplicatePool();
    }
}
