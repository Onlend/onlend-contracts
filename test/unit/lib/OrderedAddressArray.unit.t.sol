// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";

import {OrderedAddressArrayHarness} from "./mocks/OrderedAddressArrayHarness.sol";

contract OrderedAddressArrayUnitTest is Test {
    address internal constant A = address(0xA);
    address internal constant B = address(0xB);
    address internal constant C = address(0xC);
    address internal constant D = address(0xD);

    OrderedAddressArrayHarness internal harness;

    function setUp() public {
        harness = new OrderedAddressArrayHarness();
    }

    // insertAt()

    function test_insertAt_AppendsToEmptyArray() public {
        harness.insertAt(A, 0);

        assertEq(harness.values(), _array(A));
    }

    function test_insertAt_InsertsAtBeginning() public {
        harness.setValues(_array(A, B, C));

        harness.insertAt(D, 0);

        assertEq(harness.values(), _array(D, A, B, C));
    }

    function test_insertAt_InsertsInMiddle() public {
        harness.setValues(_array(A, B, C));

        harness.insertAt(D, 1);

        assertEq(harness.values(), _array(A, D, B, C));
    }

    function test_insertAt_AppendsWhenIndexEqualsLength() public {
        harness.setValues(_array(A, B, C));

        harness.insertAt(D, 3);

        assertEq(harness.values(), _array(A, B, C, D));
    }

    function test_insertAt_InsertsBeforeLastElement() public {
        harness.setValues(_array(A, B, C));

        harness.insertAt(D, 2);

        assertEq(harness.values(), _array(A, B, D, C));
    }

    function test_insertAt_AllowsDuplicateValues() public {
        harness.setValues(_array(A, B));

        harness.insertAt(A, 1);

        assertEq(harness.values(), _array(A, A, B));
    }

    function test_insertAt_RevertsWhenIndexIsAboveLength() public {
        harness.setValues(_array(A, B, C));

        vm.expectRevert(stdError.indexOOBError);
        harness.insertAt(D, 4);
    }

    function test_insertAt_RevertsWhenIndexIsAboveLengthOfEmptyArray() public {
        vm.expectRevert(stdError.indexOOBError);
        harness.insertAt(A, 1);
    }

    // removeAt()

    function test_removeAt_RemovesOnlyElement() public {
        harness.setValues(_array(A));

        harness.removeAt(0);

        assertEq(harness.length(), 0);
    }

    function test_removeAt_RemovesFirstElement() public {
        harness.setValues(_array(A, B, C));

        harness.removeAt(0);

        assertEq(harness.values(), _array(B, C));
    }

    function test_removeAt_RemovesMiddleElement() public {
        harness.setValues(_array(A, B, C));

        harness.removeAt(1);

        assertEq(harness.values(), _array(A, C));
    }

    function test_removeAt_RemovesLastElement() public {
        harness.setValues(_array(A, B, C));

        harness.removeAt(2);

        assertEq(harness.values(), _array(A, B));
    }

    function test_removeAt_ReturnsRemovedValue() public {
        harness.setValues(_array(A, B, C));

        address removed = harness.removeAt(1);

        assertEq(removed, B);
    }

    function test_removeAt_RemovesOnlyTheElementAtIndexWhenValueIsDuplicated() public {
        harness.setValues(_array(A, B, A));

        harness.removeAt(0);

        assertEq(harness.values(), _array(B, A));
    }

    function test_removeAt_RevertsWhenIndexEqualsLength() public {
        harness.setValues(_array(A, B, C));

        vm.expectRevert(stdError.indexOOBError);
        harness.removeAt(3);
    }

    function test_removeAt_RevertsWhenArrayIsEmpty() public {
        vm.expectRevert(stdError.indexOOBError);
        harness.removeAt(0);
    }

    // indexOf()

    function test_indexOf_FindsFirstElement() public {
        harness.setValues(_array(A, B, C));

        (bool found, uint256 index) = harness.indexOf(A);

        assertTrue(found);
        assertEq(index, 0);
    }

    function test_indexOf_FindsMiddleElement() public {
        harness.setValues(_array(A, B, C));

        (bool found, uint256 index) = harness.indexOf(B);

        assertTrue(found);
        assertEq(index, 1);
    }

    function test_indexOf_FindsLastElement() public {
        harness.setValues(_array(A, B, C));

        (bool found, uint256 index) = harness.indexOf(C);

        assertTrue(found);
        assertEq(index, 2);
    }

    function test_indexOf_ReturnsFirstOccurrenceWhenValueIsDuplicated() public {
        harness.setValues(_array(A, B, B));

        (bool found, uint256 index) = harness.indexOf(B);

        assertTrue(found);
        assertEq(index, 1);
    }

    function test_indexOf_ReturnsFalseWhenValueIsAbsent() public {
        harness.setValues(_array(A, B, C));

        (bool found, uint256 index) = harness.indexOf(D);

        assertFalse(found);
        assertEq(index, 0);
    }

    function test_indexOf_ReturnsFalseWhenArrayIsEmpty() public view {
        (bool found, uint256 index) = harness.indexOf(A);

        assertFalse(found);
        assertEq(index, 0);
    }

    function _array(address value0) private pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = value0;
    }

    function _array(address value0, address value1) private pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = value0;
        arr[1] = value1;
    }

    function _array(address value0, address value1, address value2) private pure returns (address[] memory arr) {
        arr = new address[](3);
        arr[0] = value0;
        arr[1] = value1;
        arr[2] = value2;
    }

    function _array(address value0, address value1, address value2, address value3)
        private
        pure
        returns (address[] memory arr)
    {
        arr = new address[](4);
        arr[0] = value0;
        arr[1] = value1;
        arr[2] = value2;
        arr[3] = value3;
    }
}
