// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {NodeDefinition} from "../NodeDefinition.sol";
import {NodeOutput} from "../NodeOutput.sol";
import {IAggregatorV3} from "../../interfaces/external/IAggregatorV3.sol";

/// @title  SequencerUptimeNode
/// @notice Gates a parent node on an L2 sequencer uptime feed, rejecting prices while the sequencer is down and for a
///         grace period after it restarts.
/// @dev    While the sequencer is down, price feeds stop updating and transactions forced in through the L1 would be
///         priced with the last values before the outage. Wrap the whole price graph of an asset in this node so that
///         every read is gated.
///
///         The uptime feed is updated from L1 through the same queue as transactions forced in through the L1, which
///         runs in order once the sequencer is back. A transaction queued before the feed's "down" update therefore
///         still sees the sequencer as up.
///
///         The grace period gives borrowers time to repay before loans that became liquidatable during the outage can
///         be liquidated. It rejects every read of the gated price, not only liquidations, and liquidations stay
///         blocked even if prices keep moving, so bad debt can grow meanwhile. A zero grace period disables it.
library SequencerUptimeNode {
    /// @notice Thrown when the uptime feed reports the sequencer as down, or reports an unexpected status.
    /// @param  sequencerUptimeFeed  Address of the sequencer uptime feed
    error SequencerDown(address sequencerUptimeFeed);

    /// @notice Thrown when the sequencer came back up less than the grace period ago.
    /// @param  sequencerUptimeFeed  Address of the sequencer uptime feed
    error GracePeriodNotOver(address sequencerUptimeFeed);

    /// @notice Processes a SEQUENCER_UPTIME node and returns its output.
    /// @dev    Returns the parent output unchanged when the feed answers 0 (up) and at least `gracePeriod` seconds have
    ///         passed since `startedAt`, the time the feed last changed status. Any other answer, including 1 (down),
    ///         reverts with `SequencerDown`, so unexpected values fail closed. A `startedAt` in the future reverts on
    ///         underflow, even with a zero grace period. A zero `startedAt` is not rejected. Reverts from the feed are
    ///         bubbled up. The parent is processed before this node, so a parent that reverts during the
    ///         outage, such as a stale STALENESS_CIRCUIT_BREAKER without fallback, surfaces its own error instead.
    /// @param  parentNodeOutputs  Output of the single parent node being gated
    /// @param  parameters         ABI-encoded sequencer uptime feed address and uint256 grace period in seconds
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        internal
        view
        returns (NodeOutput.Data memory)
    {
        (address sequencerUptimeFeed, uint256 gracePeriod) = abi.decode(parameters, (address, uint256));

        (, int256 answer, uint256 startedAt,,) = IAggregatorV3(sequencerUptimeFeed).latestRoundData();
        if (answer != 0) revert SequencerDown(sequencerUptimeFeed);

        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp - startedAt < gracePeriod) revert GracePeriodNotOver(sequencerUptimeFeed);

        return parentNodeOutputs[0];
    }

    /// @notice Returns true when the node definition is valid for a SEQUENCER_UPTIME node.
    /// @dev    Calls `latestRoundData()` on the feed, so registration reverts if the call reverts or returns data that
    ///         does not decode. The sequencer status is not checked, so the node can be registered while it is down or
    ///         within the grace period. Any grace period is accepted.
    /// @param  nodeDefinition  Node definition to validate
    function isValid(NodeDefinition.Data memory nodeDefinition) internal view returns (bool) {
        if (nodeDefinition.parents.length != 1 || nodeDefinition.parameters.length != 64) return false;

        (address sequencerUptimeFeed,) = abi.decode(nodeDefinition.parameters, (address, uint256));
        IAggregatorV3(sequencerUptimeFeed).latestRoundData();

        return true;
    }
}
