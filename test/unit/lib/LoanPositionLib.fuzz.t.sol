// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {LoanPositionLib} from "src/lib/LoanPositionLib.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";

import {LoanPositionLibHarness} from "./mocks/LoanPositionLibHarness.sol";

contract LoanPositionLibFuzzTest is Test {
    using LoanPositionLib for ILendingCore.LoanPosition[];

    /// @dev Kept small: `hasDuplicatePool` is O(n²) and the functions are intended for bounded arrays.
    uint256 internal constant MAX_POSITIONS = 32;

    LoanPositionLibHarness internal harness;

    function setUp() public {
        harness = new LoanPositionLibHarness();
    }

    // truncate()

    function testFuzz_truncate_KeepsLeadingEntries(uint256 count, uint256 length) public pure {
        count = bound(count, 0, MAX_POSITIONS);
        length = bound(length, 0, count);
        ILendingCore.LoanPosition[] memory positions = _distinctPositions(count);

        ILendingCore.LoanPosition[] memory truncated = positions.truncate(length);

        assertEq(truncated.length, length);
        for (uint256 i; i < length; ++i) {
            assertEq(address(truncated[i].pool), address(_pool(i + 1)));
            assertEq(truncated[i].amount, i + 1);
        }
    }

    function testFuzz_truncate_ClampsLengthAboveArrayLength(uint256 count, uint256 length) public pure {
        count = bound(count, 0, MAX_POSITIONS);
        length = bound(length, count + 1, type(uint256).max);
        ILendingCore.LoanPosition[] memory positions = _distinctPositions(count);

        assertEq(positions.truncate(length).length, count);
    }

    // findPosition()

    function testFuzz_findPosition_ReturnsFoundWhenPoolPresent(uint256 count, uint256 target) public view {
        count = bound(count, 1, MAX_POSITIONS);
        target = bound(target, 0, count - 1);
        ILendingCore.LoanPosition[] memory positions = _distinctPositions(count);

        (bool found, uint256 index) = harness.findPosition(positions, _pool(target + 1));

        assertTrue(found);
        assertEq(index, target);
    }

    function testFuzz_findPosition_ReturnsNotFoundWhenPoolAbsent(uint256 count) public view {
        count = bound(count, 0, MAX_POSITIONS);
        ILendingCore.LoanPosition[] memory positions = _distinctPositions(count);

        (bool found, uint256 index) = harness.findPosition(positions, _pool(count + 1));

        assertFalse(found);
        assertEq(index, 0);
    }

    // hasDuplicatePool()

    function testFuzz_hasDuplicatePool_ReturnsTrueWhenPoolRepeated(uint256 count, uint256 original, uint256 repeat)
        public
        view
    {
        count = bound(count, 2, MAX_POSITIONS);
        original = bound(original, 0, count - 1);
        repeat = bound(repeat, 0, count - 1);
        vm.assume(repeat != original);
        ILendingCore.LoanPosition[] memory positions = _distinctPositions(count);
        positions[repeat].pool = positions[original].pool;

        assertTrue(harness.hasDuplicatePool(positions));
    }

    function testFuzz_hasDuplicatePool_ReturnsFalseWhenPoolsAreDistinct(uint256 count) public view {
        count = bound(count, 0, MAX_POSITIONS);
        ILendingCore.LoanPosition[] memory positions = _distinctPositions(count);

        assertFalse(harness.hasDuplicatePool(positions));
    }

    /// @dev Pools run from `address(1)` up to `address(count)`, so they are distinct by construction and
    ///      `address(count + 1)` is one the array cannot hold. Each amount repeats its pool's number, so a test can
    ///      check both fields of an entry against its index.
    function _distinctPositions(uint256 count) private pure returns (ILendingCore.LoanPosition[] memory positions) {
        positions = new ILendingCore.LoanPosition[](count);
        for (uint256 i; i < count; ++i) {
            positions[i] = ILendingCore.LoanPosition({pool: _pool(i + 1), amount: i + 1});
        }
    }

    function _pool(uint256 value) private pure returns (IPool) {
        // Callers only pass values up to MAX_POSITIONS + 1, so this cast cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        return IPool(address(uint160(value)));
    }
}
