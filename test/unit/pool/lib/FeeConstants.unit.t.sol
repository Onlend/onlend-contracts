// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {FeeConstants} from "src/pool/lib/FeeConstants.sol";

contract FeeConstantsUnitTest is Test {
    // MAX_FEE_BPS

    function test_MAX_FEE_BPS_IsOneHundredPercentInBps() public pure {
        assertEq(FeeConstants.MAX_FEE_BPS, 10_000);
    }
}
