// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {IndexYieldAdapter} from "src/onlend-managed/yield/IndexYieldAdapter.sol";
import {MockIndexSource} from "./mocks/MockIndexSource.sol";

contract IndexYieldAdapterFuzzTest is Test {
    uint256 internal constant START = 1_000_000;
    uint256 internal constant CAPACITY = 10;
    uint256 internal constant MIN_SPACING = 1 days;
    uint256 internal constant INITIAL_INDEX = 1e18;
    uint256 internal constant MAX_INDEX = type(uint128).max;
    /// @dev The adapter has no length-dependent logic beyond the search, so this only bounds the cost of each run.
    uint256 internal constant MAX_CAPACITY = 50;
    uint256 internal constant MAX_MIN_SPACING = 30 days;
    uint256 internal constant MAX_ELAPSED = 10 * 365 days;

    function setUp() public {
        vm.warp(START);
    }

    // poke()

    function testFuzz_poke_DoesNotRecordBeforeMinSpacingHasPassed(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, MIN_SPACING - 1);
        (, IndexYieldAdapter adapter) = _deploy(INITIAL_INDEX, CAPACITY, MIN_SPACING);
        vm.warp(vm.getBlockTimestamp() + elapsed);

        bool recorded = adapter.poke();

        assertFalse(recorded);
        assertEq(adapter.checkpointCount(), 1);
    }

    function testFuzz_poke_RecordsOnceMinSpacingHasPassed(uint256 elapsed) public {
        elapsed = bound(elapsed, MIN_SPACING, MAX_ELAPSED);
        (, IndexYieldAdapter adapter) = _deploy(INITIAL_INDEX, CAPACITY, MIN_SPACING);
        vm.warp(vm.getBlockTimestamp() + elapsed);

        bool recorded = adapter.poke();

        assertTrue(recorded);
        assertEq(adapter.checkpointCount(), 2);
    }

    // isValidWindow()

    function testFuzz_isValidWindow_ReturnsTrueWithinEnvelope(uint256 capacity, uint256 minSpacing, uint256 window)
        public
    {
        capacity = bound(capacity, 2, MAX_CAPACITY);
        minSpacing = bound(minSpacing, 1, MAX_MIN_SPACING);
        window = bound(window, minSpacing, (capacity - 1) * minSpacing);
        (, IndexYieldAdapter adapter) = _deploy(INITIAL_INDEX, capacity, minSpacing);

        assertTrue(adapter.isValidWindow(window));
    }

    function testFuzz_isValidWindow_ReturnsFalseBelowMinSpacing(uint256 capacity, uint256 minSpacing, uint256 window)
        public
    {
        capacity = bound(capacity, 2, MAX_CAPACITY);
        minSpacing = bound(minSpacing, 1, MAX_MIN_SPACING);
        window = bound(window, 0, minSpacing - 1);
        (, IndexYieldAdapter adapter) = _deploy(INITIAL_INDEX, capacity, minSpacing);

        assertFalse(adapter.isValidWindow(window));
    }

    function testFuzz_isValidWindow_ReturnsFalseAboveMaxWindow(uint256 capacity, uint256 minSpacing, uint256 window)
        public
    {
        capacity = bound(capacity, 2, MAX_CAPACITY);
        minSpacing = bound(minSpacing, 1, MAX_MIN_SPACING);
        window = bound(window, (capacity - 1) * minSpacing + 1, type(uint256).max);
        (, IndexYieldAdapter adapter) = _deploy(INITIAL_INDEX, capacity, minSpacing);

        assertFalse(adapter.isValidWindow(window));
    }

    // apr()

    function testFuzz_apr_IsNotNegativeWhenIndexRises(uint256 oldIndex, uint256 newIndex, uint256 elapsed) public {
        oldIndex = bound(oldIndex, 1, MAX_INDEX - 1);
        newIndex = bound(newIndex, oldIndex + 1, MAX_INDEX);

        int256 apr = _aprBetween(oldIndex, newIndex, elapsed);

        assertGe(apr, 0);
    }

    function testFuzz_apr_IsNotPositiveWhenIndexFalls(uint256 oldIndex, uint256 newIndex, uint256 elapsed) public {
        oldIndex = bound(oldIndex, 2, MAX_INDEX);
        newIndex = bound(newIndex, 1, oldIndex - 1);

        int256 apr = _aprBetween(oldIndex, newIndex, elapsed);

        assertLe(apr, 0);
    }

    function testFuzz_apr_IsZeroWhenIndexUnchanged(uint256 index, uint256 elapsed) public {
        index = bound(index, 1, MAX_INDEX);

        int256 apr = _aprBetween(index, index, elapsed);

        assertEq(apr, 0);
    }

    function testFuzz_apr_HigherGrowthNeverLowersApr(
        uint256 oldIndex,
        uint256 newIndex,
        uint256 higherNewIndex,
        uint256 elapsed
    ) public {
        oldIndex = bound(oldIndex, 1, MAX_INDEX);
        newIndex = bound(newIndex, 1, MAX_INDEX);
        higherNewIndex = bound(higherNewIndex, newIndex, MAX_INDEX);

        int256 apr = _aprBetween(oldIndex, newIndex, elapsed);
        int256 higherApr = _aprBetween(oldIndex, higherNewIndex, elapsed);

        assertGe(higherApr, apr);
    }

    function testFuzz_apr_IsUnchangedByScalingIndex(uint256 oldIndex, uint256 newIndex, uint256 scale, uint256 elapsed)
        public
    {
        scale = bound(scale, 2, 1e18);
        oldIndex = bound(oldIndex, 1, MAX_INDEX / scale);
        newIndex = bound(newIndex, 1, MAX_INDEX / scale);

        int256 apr = _aprBetween(oldIndex, newIndex, elapsed);
        int256 scaledApr = _aprBetween(oldIndex * scale, newIndex * scale, elapsed);

        assertEq(scaledApr, apr);
    }

    function testFuzz_apr_ReportsNewestCheckpointOnceBufferIsFull(
        uint256 capacity,
        uint256 minSpacing,
        uint256 window,
        uint256 gapSeed
    ) public {
        capacity = bound(capacity, 2, MAX_CAPACITY);
        minSpacing = bound(minSpacing, 1, MAX_MIN_SPACING);
        window = bound(window, minSpacing, (capacity - 1) * minSpacing);
        (MockIndexSource source, IndexYieldAdapter adapter) = _deploy(INITIAL_INDEX, capacity, minSpacing);
        for (uint256 i = 1; i < capacity; i++) {
            uint256 gap = bound(uint256(keccak256(abi.encode(gapSeed, i))), minSpacing, 3 * minSpacing);
            vm.warp(vm.getBlockTimestamp() + gap);
            source.setIndex(INITIAL_INDEX + i);
            adapter.poke();
        }

        (, uint256 updatedAt) = adapter.apr(window);

        assertEq(updatedAt, vm.getBlockTimestamp());
    }

    /// @dev Any window, including those `isValidWindow` rejects, over any index history up to twice around the buffer.
    function testFuzz_apr_NeverReverts(
        uint256 capacity,
        uint256 minSpacing,
        uint256 pokes,
        uint256 seed,
        uint256 window
    ) public {
        capacity = bound(capacity, 2, MAX_CAPACITY);
        minSpacing = bound(minSpacing, 1, MAX_MIN_SPACING);
        pokes = bound(pokes, 0, 2 * capacity);
        (MockIndexSource source, IndexYieldAdapter adapter) = _deploy(INITIAL_INDEX, capacity, minSpacing);
        for (uint256 i; i < pokes; i++) {
            uint256 gap = bound(uint256(keccak256(abi.encode(seed, i, "gap"))), minSpacing, 3 * minSpacing);
            vm.warp(vm.getBlockTimestamp() + gap);
            source.setIndex(bound(uint256(keccak256(abi.encode(seed, i, "index"))), 1, MAX_INDEX));
            adapter.poke();
        }

        adapter.apr(window);
    }

    /// @dev Records `oldIndex`, then `newIndex` after `elapsed`, and returns the APR measured between them.
    function _aprBetween(uint256 oldIndex, uint256 newIndex, uint256 elapsed) internal returns (int256 apr) {
        elapsed = bound(elapsed, MIN_SPACING, MAX_ELAPSED);
        (MockIndexSource source, IndexYieldAdapter adapter) = _deploy(oldIndex, CAPACITY, MIN_SPACING);
        vm.warp(vm.getBlockTimestamp() + elapsed);
        source.setIndex(newIndex);
        adapter.poke();

        (apr,) = adapter.apr(MIN_SPACING);
    }

    function _deploy(uint256 index, uint256 capacity, uint256 minSpacing)
        internal
        returns (MockIndexSource source, IndexYieldAdapter adapter)
    {
        source = new MockIndexSource(index);
        adapter =
            new IndexYieldAdapter(address(source), abi.encodeCall(MockIndexSource.index, ()), capacity, minSpacing);
    }
}
