// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {MathUtils} from "../../lib/MathUtils.sol";

/// @title Fee Constants
/// @notice Fee bounds shared by the fee registry and the pools that apply its fees.
library FeeConstants {
    /// @notice Maximum supported fee of 100%, in basis points.
    uint16 internal constant MAX_FEE_BPS = uint16(MathUtils.ONE_4_DP);
}
