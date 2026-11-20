// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";

import {OrderedAddressArrayHarness} from "./mocks/OrderedAddressArrayHarness.sol";

contract OrderedAddressArrayFuzzTest is Test {
    /// @dev Kept small: insert and remove are O(n) and intended for bounded arrays.
    uint256 internal constant MAX_SIZE = 32;
    /// @dev Values seeded by `_seed` are `address(1)` up to `address(MAX_SIZE)`, so any address above that is absent.
    // MAX_SIZE is 32, so this cast cannot truncate.
    // forge-lint: disable-next-line(unsafe-typecast)
    uint160 internal constant FIRST_ABSENT_VALUE = uint160(MAX_SIZE) + 1;

    OrderedAddressArrayHarness internal harness;

    function setUp() public {
        harness = new OrderedAddressArrayHarness();
    }

    // insertAt()

    function testFuzz_insertAt_InsertsValueAndShiftsSubsequentElements(uint256 size, uint256 index) public {
        size = bound(size, 0, MAX_SIZE);
        index = bound(index, 0, size);
        address[] memory seeded = _seed(size);
        address value = address(FIRST_ABSENT_VALUE);
        harness.setValues(seeded);

        harness.insertAt(value, index);

        address[] memory result = harness.values();
        assertEq(result.length, size + 1);
        assertEq(result[index], value);
        for (uint256 i; i < index; i++) {
            assertEq(result[i], seeded[i]);
        }
        for (uint256 i = index; i < size; i++) {
            assertEq(result[i + 1], seeded[i]);
        }
    }

    function testFuzz_insertAt_RevertsWhenIndexIsAboveLength(uint256 size, uint256 index) public {
        size = bound(size, 0, MAX_SIZE);
        index = bound(index, size + 1, type(uint256).max);
        harness.setValues(_seed(size));

        vm.expectRevert(stdError.indexOOBError);
        harness.insertAt(address(FIRST_ABSENT_VALUE), index);
    }

    // removeAt()

    function testFuzz_removeAt_RemovesValueAndShiftsSubsequentElements(uint256 size, uint256 index) public {
        size = bound(size, 1, MAX_SIZE);
        index = bound(index, 0, size - 1);
        address[] memory seeded = _seed(size);
        harness.setValues(seeded);

        address removed = harness.removeAt(index);

        address[] memory result = harness.values();
        assertEq(removed, seeded[index]);
        assertEq(result.length, size - 1);
        for (uint256 i; i < index; i++) {
            assertEq(result[i], seeded[i]);
        }
        for (uint256 i = index; i < size - 1; i++) {
            assertEq(result[i], seeded[i + 1]);
        }
    }

    function testFuzz_removeAt_RevertsWhenIndexIsOutOfBounds(uint256 size, uint256 index) public {
        size = bound(size, 0, MAX_SIZE);
        index = bound(index, size, type(uint256).max);
        harness.setValues(_seed(size));

        vm.expectRevert(stdError.indexOOBError);
        harness.removeAt(index);
    }

    // indexOf()

    function testFuzz_indexOf_ReturnsTrueWhenValueIsPresent(uint256 size, uint256 index) public {
        size = bound(size, 1, MAX_SIZE);
        index = bound(index, 0, size - 1);
        address[] memory seeded = _seed(size);
        harness.setValues(seeded);

        (bool found, uint256 foundIndex) = harness.indexOf(seeded[index]);

        assertTrue(found);
        assertEq(foundIndex, index);
    }

    function testFuzz_indexOf_ReturnsFalseWhenValueIsAbsent(uint256 size, uint160 rawValue) public {
        size = bound(size, 0, MAX_SIZE);
        address value = address(uint160(bound(rawValue, FIRST_ABSENT_VALUE, type(uint160).max)));
        harness.setValues(_seed(size));

        (bool found, uint256 index) = harness.indexOf(value);

        assertFalse(found);
        assertEq(index, 0);
    }

    function _seed(uint256 size) private pure returns (address[] memory seeded) {
        seeded = new address[](size);
        for (uint256 i; i < size; i++) {
            // Every caller bounds size to MAX_SIZE, so i + 1 fits in uint160.
            // forge-lint: disable-next-line(unsafe-typecast)
            seeded[i] = address(uint160(i + 1));
        }
    }
}
