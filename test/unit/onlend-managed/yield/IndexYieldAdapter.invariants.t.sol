// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {IndexYieldAdapter} from "src/onlend-managed/yield/IndexYieldAdapter.sol";
import {MockIndexSource} from "./mocks/MockIndexSource.sol";

/// @notice Stateful handler driving the adapter through pokes at fuzzed indices (`poke`) and gaps between them
///         (`passTime`), standing in for keepers.
/// @dev    Every action is guarded so the handler never reverts.
///
///         Expectations recorded for invariants to check against:
///         - `recordedCount` — checkpoints recorded since deployment, including the initial one.
///         - `newestTimestamp` / `newestIndex` — the checkpoint the last successful poke recorded.
// forge-lint: disable-next-line(multi-contract-file)
contract IndexYieldAdapterHandler is Test {
    uint256 internal constant MAX_INDEX = type(uint128).max;

    IndexYieldAdapter public adapter;
    MockIndexSource public source;
    uint256 public maxWindow;
    uint256 public recordedCount;
    uint256 public newestTimestamp;
    uint256 public newestIndex;

    constructor(IndexYieldAdapter adapter_, MockIndexSource source_, uint256 maxWindow_) {
        adapter = adapter_;
        source = source_;
        maxWindow = maxWindow_;
        recordedCount = 1;
        (newestTimestamp, newestIndex) = adapter_.checkpoint(0);
    }

    /// @dev Pokes at a fuzzed index, below the newest recorded one if `falls` and at or above it otherwise. Records the
    ///      checkpoint if the poke did.
    function poke(uint256 indexSeed, bool falls) external {
        uint256 index =
            falls && newestIndex > 1 ? bound(indexSeed, 1, newestIndex - 1) : bound(indexSeed, newestIndex, MAX_INDEX);
        source.setIndex(index);

        if (!adapter.poke()) return;

        recordedCount++;
        newestTimestamp = vm.getBlockTimestamp();
        newestIndex = index;
    }

    /// @dev Advances time between pokes, by up to the maximum window; longer gaps behave no differently, since the
    ///      previous checkpoint is then old enough for every valid window.
    function passTime(uint256 elapsed) external {
        vm.warp(vm.getBlockTimestamp() + bound(elapsed, 1, maxWindow));
    }
}

// forge-lint: disable-next-line(multi-contract-file)
contract IndexYieldAdapterInvariantsTest is Test {
    uint256 internal constant START = 1_000_000;
    uint256 internal constant CAPACITY = 8;
    uint256 internal constant MIN_SPACING = 1 days;
    uint256 internal constant MAX_WINDOW = (CAPACITY - 1) * MIN_SPACING;
    uint256 internal constant INITIAL_INDEX = 1e18;

    IndexYieldAdapter internal adapter;
    IndexYieldAdapterHandler internal handler;

    function setUp() public {
        vm.warp(START);
        MockIndexSource source = new MockIndexSource(INITIAL_INDEX);
        adapter =
            new IndexYieldAdapter(address(source), abi.encodeCall(MockIndexSource.index, ()), CAPACITY, MIN_SPACING);
        handler = new IndexYieldAdapterHandler(adapter, source, MAX_WINDOW);

        targetContract(address(handler));
    }

    function invariant_CheckpointCountMatchesRecordedUpToCapacity() public view {
        uint256 recordedCount = handler.recordedCount();

        assertEq(adapter.checkpointCount(), recordedCount < CAPACITY ? recordedCount : CAPACITY);
    }

    function invariant_NewestCheckpointIsLastRecorded() public view {
        (uint256 timestamp, uint256 index) = adapter.checkpoint(0);

        assertEq(timestamp, handler.newestTimestamp());
        assertEq(index, handler.newestIndex());
    }

    function invariant_CheckpointsAreAtLeastMinSpacingApart() public view {
        uint256 count = adapter.checkpointCount();

        for (uint256 i = 1; i < count; i++) {
            (uint256 newer,) = adapter.checkpoint(i - 1);
            (uint256 older,) = adapter.checkpoint(i);
            assertGe(newer - older, MIN_SPACING);
        }
    }

    function invariant_AprReportsNewestCheckpointOrNothing() public view {
        uint256[3] memory windows = [MIN_SPACING, MAX_WINDOW / 2, MAX_WINDOW];

        for (uint256 i; i < windows.length; i++) {
            (int256 apr, uint256 updatedAt) = adapter.apr(windows[i]);
            if (updatedAt == 0) assertEq(apr, 0);
            else assertEq(updatedAt, handler.newestTimestamp());
        }
    }
}
