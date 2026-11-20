// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {FixedRetentionRate} from "src/pool/irm/libraries/retention-rate/FixedRetentionRate.sol";

contract FixedRetentionRateUnitTest is Test {
    uint256 internal constant RETENTION_RATE = 0.1e18;

    // isValid()

    function test_isValid_ReturnsTrueForValidParams() public pure {
        assertTrue(FixedRetentionRate.isValid(abi.encode(RETENTION_RATE)));
    }

    function test_isValid_ReturnsTrueForMaxRetentionRate() public pure {
        assertTrue(FixedRetentionRate.isValid(abi.encode(IRMConstants.MAX_RETENTION_RATE)));
    }

    function test_isValid_ReturnsFalseWhenParamsAreEmpty() public pure {
        assertFalse(FixedRetentionRate.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsAbove32() public pure {
        assertFalse(FixedRetentionRate.isValid(new bytes(33)));
    }

    function test_isValid_ReturnsFalseWhenRetentionRateIsTooHigh() public pure {
        assertFalse(FixedRetentionRate.isValid(abi.encode(IRMConstants.MAX_RETENTION_RATE + 1)));
    }

    // retentionRate()

    function test_retentionRate_ReturnsFixedRate() public pure {
        assertEq(FixedRetentionRate.retentionRate(abi.encode(RETENTION_RATE), 0, 0, 0), RETENTION_RATE);
    }

    function test_retentionRate_IgnoresMarketInputs() public pure {
        assertEq(FixedRetentionRate.retentionRate(abi.encode(RETENTION_RATE), 100e18, 50e18, 25e18), RETENTION_RATE);
    }

    function test_retentionRate_RevertsWhenParamsCannotBeDecoded() public {
        vm.expectRevert();
        this.retentionRate("");
    }

    function retentionRate(bytes memory params) external pure returns (uint256) {
        return FixedRetentionRate.retentionRate(params, 0, 0, 0);
    }
}
