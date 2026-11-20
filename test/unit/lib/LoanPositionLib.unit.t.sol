// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {LoanPositionLib} from "src/lib/LoanPositionLib.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";

import {LoanHelpers} from "../../helpers/LoanHelpers.sol";
import {LoanPositionLibHarness} from "./mocks/LoanPositionLibHarness.sol";

contract LoanPositionLibUnitTest is Test {
    using LoanPositionLib for ILendingCore.LoanPosition[];

    LoanPositionLibHarness internal harness;

    IPool internal firstPool;
    IPool internal secondPool;
    IPool internal thirdPool;

    function setUp() public {
        harness = new LoanPositionLibHarness();

        firstPool = IPool(makeAddr("firstPool"));
        secondPool = IPool(makeAddr("secondPool"));
        thirdPool = IPool(makeAddr("thirdPool"));
    }

    // truncate()

    function test_truncate_KeepsLeadingEntries() public view {
        ILendingCore.LoanPosition[] memory positions =
            LoanHelpers.positions(firstPool, 10e18, secondPool, 20e18, thirdPool, 30e18);

        ILendingCore.LoanPosition[] memory truncated = positions.truncate(2);

        assertEq(truncated.length, 2);
        assertEq(address(truncated[0].pool), address(firstPool));
        assertEq(truncated[0].amount, 10e18);
        assertEq(address(truncated[1].pool), address(secondPool));
        assertEq(truncated[1].amount, 20e18);
    }

    function test_truncate_ShortensArrayInPlace() public view {
        ILendingCore.LoanPosition[] memory positions =
            LoanHelpers.positions(firstPool, 10e18, secondPool, 20e18, thirdPool, 30e18);

        positions.truncate(1);

        assertEq(positions.length, 1);
    }

    function test_truncate_ReturnsSameArray() public view {
        ILendingCore.LoanPosition[] memory positions =
            LoanHelpers.positions(firstPool, 10e18, secondPool, 20e18, thirdPool, 30e18);
        ILendingCore.LoanPosition[] memory truncated = positions.truncate(2);

        truncated.truncate(1);

        assertEq(positions.length, 1);
    }

    function test_truncate_ReturnsEmptyForZeroLength() public view {
        ILendingCore.LoanPosition[] memory positions = LoanHelpers.positions(firstPool, 10e18, secondPool, 20e18);

        assertEq(positions.truncate(0).length, 0);
    }

    function test_truncate_KeepsWholeArrayAtItsOwnLength() public view {
        ILendingCore.LoanPosition[] memory positions = LoanHelpers.positions(firstPool, 10e18, secondPool, 20e18);

        assertEq(positions.truncate(2).length, 2);
    }

    function test_truncate_ClampsLengthAboveArrayLength() public view {
        ILendingCore.LoanPosition[] memory positions = LoanHelpers.positions(firstPool, 10e18, secondPool, 20e18);

        assertEq(positions.truncate(3).length, 2);
    }

    // findPosition()

    function test_findPosition_ReturnsIndexOfMatchingPool() public view {
        ILendingCore.LoanPosition[] memory positions = LoanHelpers.positions(firstPool, 10e18, secondPool, 20e18);

        (bool found, uint256 index) = harness.findPosition(positions, secondPool);

        assertTrue(found);
        assertEq(index, 1);
    }

    function test_findPosition_ReturnsFirstMatchWhenPoolRepeated() public view {
        ILendingCore.LoanPosition[] memory positions = LoanHelpers.positions(firstPool, 10e18, firstPool, 20e18);

        (bool found, uint256 index) = harness.findPosition(positions, firstPool);

        assertTrue(found);
        assertEq(index, 0);
    }

    function test_findPosition_ReturnsNotFoundWhenPoolAbsent() public view {
        ILendingCore.LoanPosition[] memory positions = LoanHelpers.positions(firstPool, 10e18, secondPool, 20e18);

        (bool found, uint256 index) = harness.findPosition(positions, thirdPool);

        assertFalse(found);
        assertEq(index, 0);
    }

    function test_findPosition_ReturnsNotFoundForEmptyArray() public view {
        ILendingCore.LoanPosition[] memory positions = LoanHelpers.noPositions();

        (bool found, uint256 index) = harness.findPosition(positions, firstPool);

        assertFalse(found);
        assertEq(index, 0);
    }

    // hasDuplicatePool()

    function test_hasDuplicatePool_ReturnsTrueForAdjacentRepeat() public view {
        ILendingCore.LoanPosition[] memory positions = LoanHelpers.positions(firstPool, 10e18, firstPool, 20e18);

        assertTrue(harness.hasDuplicatePool(positions));
    }

    function test_hasDuplicatePool_ReturnsTrueForSeparatedRepeat() public view {
        ILendingCore.LoanPosition[] memory positions =
            LoanHelpers.positions(firstPool, 10e18, secondPool, 20e18, firstPool, 30e18);

        assertTrue(harness.hasDuplicatePool(positions));
    }

    function test_hasDuplicatePool_ReturnsFalseWhenPoolsAreDistinct() public view {
        ILendingCore.LoanPosition[] memory positions = LoanHelpers.positions(firstPool, 10e18, secondPool, 20e18);

        assertFalse(harness.hasDuplicatePool(positions));
    }

    function test_hasDuplicatePool_ReturnsFalseWhenOnlyAmountsRepeat() public view {
        ILendingCore.LoanPosition[] memory positions = LoanHelpers.positions(firstPool, 10e18, secondPool, 10e18);

        assertFalse(harness.hasDuplicatePool(positions));
    }

    function test_hasDuplicatePool_ReturnsFalseForSinglePosition() public view {
        ILendingCore.LoanPosition[] memory positions = LoanHelpers.positions(firstPool, 10e18);

        assertFalse(harness.hasDuplicatePool(positions));
    }

    function test_hasDuplicatePool_ReturnsFalseForEmptyArray() public view {
        ILendingCore.LoanPosition[] memory positions = LoanHelpers.noPositions();

        assertFalse(harness.hasDuplicatePool(positions));
    }
}
