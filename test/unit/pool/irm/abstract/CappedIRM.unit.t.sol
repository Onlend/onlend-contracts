// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {CappedIRMHarness} from "./mocks/CappedIRMHarness.sol";

contract CappedIRMUnitTest is Test {
    CappedIRMHarness internal irm;

    function setUp() public {
        irm = new CappedIRMHarness();
    }

    function test_borrowRate_ReturnsRateAtCap() public {
        irm.setUncappedBorrowRate(IRMConstants.MAX_BORROW_RATE);

        assertEq(irm.borrowRate(100e18, 50e18, 25e18), IRMConstants.MAX_BORROW_RATE);
    }

    function test_borrowRate_CapsRateAboveCap() public {
        irm.setUncappedBorrowRate(IRMConstants.MAX_BORROW_RATE + 1);

        assertEq(irm.borrowRate(100e18, 50e18, 25e18), IRMConstants.MAX_BORROW_RATE);
    }

    function test_previewBorrowRate_ReturnsRateAtCap() public {
        irm.setUncappedPreviewBorrowRate(IRMConstants.MAX_BORROW_RATE);

        assertEq(irm.previewBorrowRate(100e18, 50e18, 25e18), IRMConstants.MAX_BORROW_RATE);
    }

    function test_previewBorrowRate_CapsRateAboveCap() public {
        irm.setUncappedPreviewBorrowRate(IRMConstants.MAX_BORROW_RATE + 1);

        assertEq(irm.previewBorrowRate(100e18, 50e18, 25e18), IRMConstants.MAX_BORROW_RATE);
    }

    function test_retentionRate_ReturnsRateAtCap() public {
        irm.setUncappedRetentionRate(IRMConstants.MAX_RETENTION_RATE);

        assertEq(irm.retentionRate(100e18, 50e18, 25e18), IRMConstants.MAX_RETENTION_RATE);
    }

    function test_retentionRate_CapsRateAboveCap() public {
        irm.setUncappedRetentionRate(IRMConstants.MAX_RETENTION_RATE + 1);

        assertEq(irm.retentionRate(100e18, 50e18, 25e18), IRMConstants.MAX_RETENTION_RATE);
    }
}
