// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {CappedIRMHarness} from "./mocks/CappedIRMHarness.sol";

contract CappedIRMFuzzTest is Test {
    CappedIRMHarness internal irm;

    function setUp() public {
        irm = new CappedIRMHarness();
    }

    function testFuzz_borrowRate_ReturnsRateWhenAtOrBelowCap(uint256 rate) public {
        rate = bound(rate, 0, IRMConstants.MAX_BORROW_RATE);
        irm.setUncappedBorrowRate(rate);

        assertEq(irm.borrowRate(100e18, 50e18, 25e18), rate);
    }

    function testFuzz_borrowRate_ReturnsCapWhenAboveCap(uint256 rate) public {
        rate = bound(rate, IRMConstants.MAX_BORROW_RATE + 1, type(uint256).max);
        irm.setUncappedBorrowRate(rate);

        assertEq(irm.borrowRate(100e18, 50e18, 25e18), IRMConstants.MAX_BORROW_RATE);
    }

    function testFuzz_previewBorrowRate_ReturnsRateWhenAtOrBelowCap(uint256 rate) public {
        rate = bound(rate, 0, IRMConstants.MAX_BORROW_RATE);
        irm.setUncappedPreviewBorrowRate(rate);

        assertEq(irm.previewBorrowRate(100e18, 50e18, 25e18), rate);
    }

    function testFuzz_previewBorrowRate_ReturnsCapWhenAboveCap(uint256 rate) public {
        rate = bound(rate, IRMConstants.MAX_BORROW_RATE + 1, type(uint256).max);
        irm.setUncappedPreviewBorrowRate(rate);

        assertEq(irm.previewBorrowRate(100e18, 50e18, 25e18), IRMConstants.MAX_BORROW_RATE);
    }

    function testFuzz_retentionRate_ReturnsRateWhenAtOrBelowCap(uint256 rate) public {
        rate = bound(rate, 0, IRMConstants.MAX_RETENTION_RATE);
        irm.setUncappedRetentionRate(rate);

        assertEq(irm.retentionRate(100e18, 50e18, 25e18), rate);
    }

    function testFuzz_retentionRate_ReturnsCapWhenAboveCap(uint256 rate) public {
        rate = bound(rate, IRMConstants.MAX_RETENTION_RATE + 1, type(uint256).max);
        irm.setUncappedRetentionRate(rate);

        assertEq(irm.retentionRate(100e18, 50e18, 25e18), IRMConstants.MAX_RETENTION_RATE);
    }
}
