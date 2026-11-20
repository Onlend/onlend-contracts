// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IndexYieldAdapter} from "src/onlend-managed/yield/IndexYieldAdapter.sol";
import {IYieldAdapter} from "src/pool/irm/interfaces/IYieldAdapter.sol";
import {MockIndexSource} from "./mocks/MockIndexSource.sol";

contract IndexYieldAdapterUnitTest is Test {
    uint256 internal constant START = 1_000_000;
    uint256 internal constant CAPACITY = 5;
    /// @dev A tenth of a year, so 1% of growth over one spacing is exactly a 10% APR.
    uint256 internal constant MIN_SPACING = 365 days / 10;
    uint256 internal constant MAX_WINDOW = (CAPACITY - 1) * MIN_SPACING;
    uint256 internal constant INITIAL_INDEX = 1e18;
    uint256 internal constant GROWN_INDEX = 1.01e18;

    MockIndexSource internal source;
    bytes internal indexCall;
    IndexYieldAdapter internal adapter;

    function setUp() public {
        vm.warp(START);
        source = new MockIndexSource(INITIAL_INDEX);
        indexCall = abi.encodeCall(MockIndexSource.index, ());
        adapter = new IndexYieldAdapter(address(source), indexCall, CAPACITY, MIN_SPACING);
    }

    // constructor()

    function test_constructor_SetsTarget() public view {
        assertEq(adapter.TARGET(), address(source));
    }

    function test_constructor_SetsMinSpacing() public view {
        assertEq(adapter.MIN_SPACING(), MIN_SPACING);
    }

    function test_constructor_SetsCallData() public view {
        assertEq(adapter.callData(), indexCall);
    }

    function test_constructor_SetsCapacity() public view {
        assertEq(adapter.capacity(), CAPACITY);
    }

    function test_constructor_RecordsInitialCheckpoint() public view {
        (uint256 timestamp, uint256 index) = adapter.checkpoint(0);

        assertEq(adapter.checkpointCount(), 1);
        assertEq(timestamp, START);
        assertEq(index, INITIAL_INDEX);
    }

    function test_constructor_EmitsCheckpointed() public {
        vm.expectEmit();
        emit IndexYieldAdapter.Checkpointed(SafeCast.toUint48(START), SafeCast.toUint128(INITIAL_INDEX));

        new IndexYieldAdapter(address(source), indexCall, CAPACITY, MIN_SPACING);
    }

    function test_constructor_AcceptsMinCapacity() public {
        IndexYieldAdapter minAdapter = new IndexYieldAdapter(address(source), indexCall, 2, MIN_SPACING);

        assertEq(minAdapter.capacity(), 2);
    }

    function test_constructor_AcceptsMinSpacingOfOne() public {
        IndexYieldAdapter minAdapter = new IndexYieldAdapter(address(source), indexCall, CAPACITY, 1);

        assertEq(minAdapter.MIN_SPACING(), 1);
    }

    function test_constructor_Revert_CapacityBelowTwo() public {
        vm.expectRevert(abi.encodeWithSelector(IndexYieldAdapter.InvalidCapacity.selector, 1));
        new IndexYieldAdapter(address(source), indexCall, 1, MIN_SPACING);
    }

    function test_constructor_Revert_ZeroMinSpacing() public {
        vm.expectRevert(IndexYieldAdapter.InvalidMinSpacing.selector);
        new IndexYieldAdapter(address(source), indexCall, CAPACITY, 0);
    }

    function test_constructor_Revert_TargetHasNoCode() public {
        address target = makeAddr("target");

        vm.expectRevert(abi.encodeWithSelector(Address.AddressEmptyCode.selector, target));
        new IndexYieldAdapter(target, indexCall, CAPACITY, MIN_SPACING);
    }

    function test_constructor_Revert_SourceReverts() public {
        source.setShouldRevert(true);

        vm.expectRevert(MockIndexSource.IndexReverted.selector);
        new IndexYieldAdapter(address(source), indexCall, CAPACITY, MIN_SPACING);
    }

    function test_constructor_Revert_ReturnDataDoesNotDecode() public {
        bytes memory noReturnCall = abi.encodeCall(MockIndexSource.noReturn, ());

        vm.expectRevert();
        new IndexYieldAdapter(address(source), noReturnCall, CAPACITY, MIN_SPACING);
    }

    function test_constructor_Revert_IndexAboveUint128Max() public {
        uint256 index = uint256(type(uint128).max) + 1;
        source.setIndex(index);

        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 128, index));
        new IndexYieldAdapter(address(source), indexCall, CAPACITY, MIN_SPACING);
    }

    function test_constructor_Revert_ZeroIndex() public {
        source.setIndex(0);

        vm.expectRevert(IndexYieldAdapter.ZeroIndex.selector);
        new IndexYieldAdapter(address(source), indexCall, CAPACITY, MIN_SPACING);
    }

    function test_constructor_Revert_TimestampAboveUint48Max() public {
        uint256 timestamp = uint256(type(uint48).max) + 1;
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 48, timestamp));
        new IndexYieldAdapter(address(source), indexCall, CAPACITY, MIN_SPACING);
    }

    // poke()

    function test_poke_RecordsCheckpointOnceMinSpacingHasPassed() public {
        uint256 timestamp = vm.getBlockTimestamp() + MIN_SPACING;
        vm.warp(timestamp);
        source.setIndex(GROWN_INDEX);

        bool recorded = adapter.poke();

        (uint256 checkpointTimestamp, uint256 index) = adapter.checkpoint(0);
        assertTrue(recorded);
        assertEq(adapter.checkpointCount(), 2);
        assertEq(checkpointTimestamp, timestamp);
        assertEq(index, GROWN_INDEX);
    }

    function test_poke_EmitsCheckpointed() public {
        uint256 timestamp = vm.getBlockTimestamp() + MIN_SPACING;
        vm.warp(timestamp);
        source.setIndex(GROWN_INDEX);

        vm.expectEmit(address(adapter));
        emit IndexYieldAdapter.Checkpointed(SafeCast.toUint48(timestamp), SafeCast.toUint128(GROWN_INDEX));

        adapter.poke();
    }

    function test_poke_ReturnsFalseBeforeMinSpacingHasPassed() public {
        vm.warp(vm.getBlockTimestamp() + MIN_SPACING - 1);

        bool recorded = adapter.poke();

        assertFalse(recorded);
        assertEq(adapter.checkpointCount(), 1);
    }

    function test_poke_DoesNotReadSourceBeforeMinSpacingHasPassed() public {
        vm.warp(vm.getBlockTimestamp() + MIN_SPACING - 1);
        source.setShouldRevert(true);

        bool recorded = adapter.poke();

        assertFalse(recorded);
    }

    function test_poke_OverwritesOldestCheckpointOnceFull() public {
        for (uint256 i = 1; i <= CAPACITY; i++) {
            _pokeAfter(MIN_SPACING, INITIAL_INDEX + i);
        }

        (, uint256 oldestIndex) = adapter.checkpoint(CAPACITY - 1);

        assertEq(adapter.checkpointCount(), CAPACITY);
        assertEq(oldestIndex, INITIAL_INDEX + 1);
    }

    function test_poke_Revert_SourceReverts() public {
        vm.warp(vm.getBlockTimestamp() + MIN_SPACING);
        source.setShouldRevert(true);

        vm.expectRevert(MockIndexSource.IndexReverted.selector);
        adapter.poke();
    }

    // isValidWindow()

    function test_isValidWindow_ReturnsTrueForMinSpacing() public view {
        assertTrue(adapter.isValidWindow(MIN_SPACING));
    }

    function test_isValidWindow_ReturnsTrueForMaxWindow() public view {
        assertTrue(adapter.isValidWindow(MAX_WINDOW));
    }

    function test_isValidWindow_ReturnsFalseBelowMinSpacing() public view {
        assertFalse(adapter.isValidWindow(MIN_SPACING - 1));
    }

    function test_isValidWindow_ReturnsFalseAboveMaxWindow() public view {
        assertFalse(adapter.isValidWindow(MAX_WINDOW + 1));
    }

    // apr()

    function test_apr_ReturnsAprBetweenCheckpoints() public {
        _pokeAfter(MIN_SPACING, GROWN_INDEX);

        (int256 apr,) = adapter.apr(MIN_SPACING);

        // 1% of growth over a tenth of a year.
        assertEq(apr, 0.1e18);
    }

    function test_apr_ReturnsNegativeAprWhenIndexFalls() public {
        _pokeAfter(MIN_SPACING, 0.99e18);

        (int256 apr,) = adapter.apr(MIN_SPACING);

        assertEq(apr, -0.1e18);
    }

    function test_apr_ReturnsNewestCheckpointTimestamp() public {
        _pokeAfter(MIN_SPACING, GROWN_INDEX);

        (, uint256 updatedAt) = adapter.apr(MIN_SPACING);

        assertEq(updatedAt, vm.getBlockTimestamp());
    }

    function test_apr_MeasuresOverTimeBetweenCheckpoints() public {
        _pokeAfter(2 * MIN_SPACING, GROWN_INDEX);

        (int256 apr,) = adapter.apr(MIN_SPACING);

        // 1% of growth over two tenths of a year, although the window is one tenth.
        assertEq(apr, 0.05e18);
    }

    function test_apr_UsesNewestCheckpointOldEnoughForWindow() public {
        _pokeAfter(MIN_SPACING, GROWN_INDEX);
        _pokeAfter(MIN_SPACING, 1.0201e18);

        (int256 apr,) = adapter.apr(MIN_SPACING);

        // 1% of growth from 1.01 to 1.0201, rather than 2.01% from the initial checkpoint.
        assertEq(apr, 0.1e18);
    }

    function test_apr_ReachesFurtherBackForLongerWindow() public {
        _pokeAfter(MIN_SPACING, GROWN_INDEX);
        _pokeAfter(MIN_SPACING, 1.0201e18);

        (int256 apr,) = adapter.apr(2 * MIN_SPACING);

        // 2.01% of growth from the initial checkpoint over two tenths of a year.
        assertEq(apr, 0.1005e18);
    }

    function test_apr_SkipsCheckpointsNewerThanWindow() public {
        _pokeAfter(2 * MIN_SPACING, GROWN_INDEX);
        _pokeAfter(MIN_SPACING, 1.03e18);

        (int256 apr,) = adapter.apr(2 * MIN_SPACING);

        // The middle checkpoint is only one tenth of a year old, so 3% of growth from the initial checkpoint over
        // three tenths of a year.
        assertEq(apr, 0.1e18);
    }

    function test_apr_ReturnsZeroWithOnlyInitialCheckpoint() public view {
        (int256 apr, uint256 updatedAt) = adapter.apr(MIN_SPACING);

        assertEq(apr, 0);
        assertEq(updatedAt, 0);
    }

    function test_apr_ReturnsZeroWhenWindowExceedsRecordedHistory() public {
        _pokeAfter(MIN_SPACING, GROWN_INDEX);

        (int256 apr, uint256 updatedAt) = adapter.apr(2 * MIN_SPACING);

        assertEq(apr, 0);
        assertEq(updatedAt, 0);
    }

    function test_apr_ReturnsZeroWhenWindowExceedsNewestTimestamp() public {
        _pokeAfter(MIN_SPACING, GROWN_INDEX);

        (int256 apr, uint256 updatedAt) = adapter.apr(vm.getBlockTimestamp() + 1);

        assertEq(apr, 0);
        assertEq(updatedAt, 0);
    }

    function test_apr_DoesNotReadSource() public {
        _pokeAfter(MIN_SPACING, GROWN_INDEX);
        source.setShouldRevert(true);

        (int256 apr,) = adapter.apr(MIN_SPACING);

        assertEq(apr, 0.1e18);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(adapter.contractName(), "IndexYieldAdapter");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(adapter.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_SupportsIYieldAdapter() public view {
        assertTrue(adapter.supportsInterface(type(IYieldAdapter).interfaceId));
    }

    function test_supportsInterface_SupportsIVersioned() public view {
        assertTrue(adapter.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_SupportsIERC165() public view {
        assertTrue(adapter.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_ReturnsFalseForUnsupportedInterface() public view {
        assertFalse(adapter.supportsInterface(0xffffffff));
    }

    function _pokeAfter(uint256 elapsed, uint256 index) internal {
        vm.warp(vm.getBlockTimestamp() + elapsed);
        source.setIndex(index);
        adapter.poke();
    }
}
