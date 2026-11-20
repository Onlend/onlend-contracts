// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Packing} from "@openzeppelin/contracts/utils/Packing.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {CircularBuffer} from "@openzeppelin/contracts/utils/structs/CircularBuffer.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {MathUtils} from "../../lib/MathUtils.sol";
import {IYieldAdapter} from "../../pool/irm/interfaces/IYieldAdapter.sol";

/// @title  IndexYieldAdapter
/// @notice Reports the APR implied by the growth of an on-chain index over a caller-chosen lookback window, such as an
///         ERC-4626 vault's assets per share, wstETH's stETH per token, or an Aave reserve's income index from
///         `getReserveNormalizedIncome`, which grows at its supply rate.
/// @dev    The source reports only its current level, so the adapter records its history: anyone can checkpoint the
///         index, at most once per `MIN_SPACING`, into a ring buffer of fixed capacity. The APR is measured between
///         stored checkpoints only and the source is never read when reporting it, so a source that starts reverting
///         stops new checkpoints but leaves the recorded history readable.
///
///         Capacity and minimum spacing are fixed at deployment and set the envelope of windows the adapter can serve:
///         at least `MIN_SPACING`, and at most `(capacity - 1) * MIN_SPACING`, the shortest span a full buffer can
///         cover.
///
///         Deployed once per source by Onlend and shared by every lending app that tracks it.
///
///         Security considerations, all on the operator choosing the source:
///         - Spikes: any jump in the index, such as a donation or a rewards drop, is indistinguishable from accrued
///           yield and is reported as such until it leaves the window. Whether one is possible depends on the source:
///           some count transferred-in assets immediately, while others vest rewards over time or ignore donations.
///         - Read-only reentrancy: some sources report an inconsistent index while one of their own operations is in
///           progress. Only use sources whose index is consistent whenever it can be read.
///         - Precision: the index is recorded as returned, so the call must return enough digits for growth over one
///           `MIN_SPACING` to register, e.g. `convertToAssets(1e30)` rather than one whole share of a 6-decimal vault.
///         - Liveness: checkpoints are only recorded when someone calls `poke`, so the reported APR is only as fresh as
///           the most recent call.
contract IndexYieldAdapter is IYieldAdapter {
    using CircularBuffer for CircularBuffer.Bytes32CircularBuffer;

    /// @notice Contract the index is read from.
    address public immutable TARGET;
    /// @notice Minimum time between checkpoints, in seconds.
    uint256 public immutable MIN_SPACING;

    /// @notice Calldata of the static call that returns the index, ABI-encoded as a single `uint256`.
    bytes private _callData;
    /// @notice Recorded checkpoints, each packing a `uint48` timestamp followed by a `uint128` index.
    CircularBuffer.Bytes32CircularBuffer private _checkpoints;

    /// @notice Emitted when a checkpoint is recorded.
    /// @param  timestamp Time the index was read at.
    /// @param  index     Index read from the source.
    event Checkpointed(uint48 timestamp, uint128 index);

    /// @notice Reverts when the capacity cannot hold two checkpoints to measure between.
    /// @param  capacity Invalid capacity.
    error InvalidCapacity(uint256 capacity);
    /// @notice Reverts when the minimum spacing between checkpoints is zero.
    error InvalidMinSpacing();
    /// @notice Reverts when the source reports a zero index, which no growth can be measured from.
    error ZeroIndex();

    /// @dev    Records the first checkpoint, so deployment reverts if the source cannot be read.
    /// @param  target_     Contract the index is read from.
    /// @param  callData_   Calldata of the static call that returns the index, ABI-encoded as a single `uint256`.
    /// @param  capacity_   Number of checkpoints kept; the oldest is overwritten once full.
    /// @param  minSpacing_ Minimum time between checkpoints, in seconds.
    constructor(address target_, bytes memory callData_, uint256 capacity_, uint256 minSpacing_) {
        if (capacity_ < 2) revert InvalidCapacity(capacity_);
        if (minSpacing_ == 0) revert InvalidMinSpacing();

        TARGET = target_;
        MIN_SPACING = minSpacing_;
        _callData = callData_;
        _checkpoints.setup(capacity_);

        _record();
    }

    /// @notice Records the current index as the newest checkpoint, once `MIN_SPACING` has passed since the last one.
    /// @dev    Permissionless. Returns false without reading the source when called too early, so it can be called
    ///         opportunistically. Reverts if the source cannot be read, as described in `_record`.
    /// @return recorded True if a checkpoint was recorded.
    function poke() external returns (bool recorded) {
        (uint48 latestTimestamp,) = _unpack(_checkpoints.last(0));
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp - latestTimestamp < MIN_SPACING) return false;

        _record();

        return true;
    }

    /// @inheritdoc IYieldAdapter
    /// @dev    Valid windows run from `MIN_SPACING` up to `(capacity - 1) * MIN_SPACING`, the shortest span a full
    ///         buffer can cover. The upper bound is checked as `ceil(window / MIN_SPACING) < capacity`, which is
    ///         equivalent and cannot overflow.
    function isValidWindow(uint256 window) external view override(IYieldAdapter) returns (bool) {
        return window >= MIN_SPACING && Math.ceilDiv(window, MIN_SPACING) < _checkpoints.length();
    }

    /// @inheritdoc IYieldAdapter
    /// @dev    Measured from the newest checkpoint back to the newest checkpoint at least `window` older than it, over
    ///         the time between the two, which is at least `window`. Returns `(0, 0)` while no checkpoint is old
    ///         enough, such as shortly after deployment. Rounds toward zero and never reverts.
    function apr(uint256 window) external view override(IYieldAdapter) returns (int256 apr_, uint256 updatedAt) {
        (uint48 newestTimestamp, uint128 newestIndex) = _unpack(_checkpoints.last(0));
        if (window > newestTimestamp) return (0, 0);

        (bool found, uint48 oldTimestamp, uint128 oldIndex) =
            _newestCheckpointAtOrBefore(newestTimestamp - window, window);
        if (!found) return (0, 0);

        /// @dev Cannot overflow: the index change is below `2 ** 128` in magnitude and the scale below `2 ** 85`.
        ///      Cannot divide by zero: no zero index is recorded, and the old checkpoint is at least `MIN_SPACING`
        ///      older.
        apr_ = (SafeCast.toInt256(newestIndex) - SafeCast.toInt256(oldIndex))
            * SafeCast.toInt256(MathUtils.ONE_18_DP * MathUtils.SECONDS_IN_YEAR)
            / SafeCast.toInt256(uint256(oldIndex) * (newestTimestamp - oldTimestamp));
        updatedAt = newestTimestamp;
    }

    /// @notice Returns the calldata of the static call that returns the index.
    /// @return Calldata sent to `TARGET`.
    function callData() external view returns (bytes memory) {
        return _callData;
    }

    /// @notice Returns the number of checkpoints kept before the oldest is overwritten.
    /// @return Buffer capacity.
    function capacity() external view returns (uint256) {
        return _checkpoints.length();
    }

    /// @notice Returns the number of checkpoints currently recorded.
    /// @return Checkpoint count, at most `capacity()`.
    function checkpointCount() external view returns (uint256) {
        return _checkpoints.count();
    }

    /// @notice Returns a recorded checkpoint, counting back from the newest.
    /// @dev    Reverts with an out-of-bounds panic if `i` is not below `checkpointCount()`.
    /// @param  i Position from the newest checkpoint, which is zero.
    /// @return timestamp Time the index was read at.
    /// @return index     Index read from the source.
    function checkpoint(uint256 i) external view returns (uint48 timestamp, uint128 index) {
        return _unpack(_checkpoints.last(i));
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "IndexYieldAdapter";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override(IERC165) returns (bool) {
        return interfaceId == type(IYieldAdapter).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Reads the index from the source and records it as the newest checkpoint.
    /// @dev    Reverts if the target has no code, the call reverts, its return data does not decode as a `uint256`, or
    ///         the index exceeds `type(uint128).max` or is zero.
    function _record() private {
        uint128 index = SafeCast.toUint128(abi.decode(Address.functionStaticCall(TARGET, _callData), (uint256)));
        if (index == 0) revert ZeroIndex();

        uint48 timestamp = SafeCast.toUint48(block.timestamp);
        _checkpoints.push(_pack(timestamp, index));

        emit Checkpointed(timestamp, index);
    }

    /// @notice Returns the newest checkpoint, other than the newest overall, recorded at or before a cutoff.
    /// @dev    Binary searches the buffer, whose timestamps strictly decrease from newest to oldest. Skipping the
    ///         newest checkpoint keeps the found one at least `MIN_SPACING` older than it. Checkpoints are at least
    ///         `MIN_SPACING` apart, so the one `ceil(window / MIN_SPACING)` positions back is always at or before the
    ///         cutoff, and nothing older is searched.
    /// @param  cutoff Latest timestamp the checkpoint may have.
    /// @param  window Time between the newest checkpoint and `cutoff`, in seconds.
    /// @return found     True if such a checkpoint is recorded.
    /// @return timestamp Time its index was read at; zero if not found.
    /// @return index     Its index; zero if not found.
    function _newestCheckpointAtOrBefore(uint256 cutoff, uint256 window)
        private
        view
        returns (bool found, uint48 timestamp, uint128 index)
    {
        uint256 end = Math.min(_checkpoints.count(), Math.ceilDiv(window, MIN_SPACING) + 1);
        uint256 low = 1;
        uint256 high = end;

        while (low < high) {
            uint256 mid = Math.average(low, high);
            (uint48 midTimestamp,) = _unpack(_checkpoints.last(mid));
            if (midTimestamp <= cutoff) high = mid;
            else low = mid + 1;
        }

        /// @dev The search always ends with `low == high`, and only reaches `end` when no searched checkpoint is at or
        ///      before the cutoff.
        if (low == end) return (false, 0, 0);

        (timestamp, index) = _unpack(_checkpoints.last(low));
        found = true;
    }

    /// @notice Packs a checkpoint into a buffer entry.
    /// @param  timestamp Time the index was read at.
    /// @param  index     Index read from the source.
    /// @return Buffer entry.
    function _pack(uint48 timestamp, uint128 index) private pure returns (bytes32) {
        return bytes32(Packing.pack_6_16(bytes6(timestamp), bytes16(index)));
    }

    /// @notice Unpacks a buffer entry into a checkpoint.
    /// @param  entry Buffer entry.
    /// @return timestamp Time the index was read at.
    /// @return index     Index read from the source.
    function _unpack(bytes32 entry) private pure returns (uint48 timestamp, uint128 index) {
        timestamp = uint48(Packing.extract_32_6(entry, 0));
        index = uint128(Packing.extract_32_16(entry, 6));
    }
}
