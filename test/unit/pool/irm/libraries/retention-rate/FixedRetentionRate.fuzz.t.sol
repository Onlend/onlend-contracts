// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {FixedRetentionRate} from "src/pool/irm/libraries/retention-rate/FixedRetentionRate.sol";

contract FixedRetentionRateFuzzTest is Test {
    // isValid()

    function testFuzz_isValid_ReturnsTrueWhenWithinBound(uint256 retentionRate) public pure {
        retentionRate = bound(retentionRate, 0, IRMConstants.MAX_RETENTION_RATE);

        assertTrue(FixedRetentionRate.isValid(abi.encode(retentionRate)));
    }

    function testFuzz_isValid_ReturnsFalseWhenAboveBound(uint256 retentionRate) public pure {
        retentionRate = bound(retentionRate, IRMConstants.MAX_RETENTION_RATE + 1, type(uint256).max);

        assertFalse(FixedRetentionRate.isValid(abi.encode(retentionRate)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsBelow32(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 0, 31);

        assertFalse(FixedRetentionRate.isValid(new bytes(paramsLength)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsAbove32(uint256 paramsLength) public pure {
        paramsLength = bound(paramsLength, 33, 1024);

        assertFalse(FixedRetentionRate.isValid(new bytes(paramsLength)));
    }

    // retentionRate()

    function testFuzz_retentionRate_ReturnsFixedRate(
        uint256 retentionRate,
        uint256 idleLiquidity,
        uint256 totalDebt,
        uint256 totalIrmDebt
    ) public pure {
        assertEq(
            FixedRetentionRate.retentionRate(abi.encode(retentionRate), idleLiquidity, totalDebt, totalIrmDebt),
            retentionRate
        );
    }
}
