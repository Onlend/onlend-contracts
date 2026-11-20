// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title  IAggregatorV3
/// @notice Minimal subset of the `AggregatorV3Interface` feed ABI read by the AGGREGATOR_V3 and SEQUENCER_UPTIME nodes.
/// @dev    The ABI is a de facto standard implemented by several oracle providers and adapters.
interface IAggregatorV3 {
    /// @notice Returns the number of decimal places of the answer.
    /// @return Decimal places of `answer`
    function decimals() external view returns (uint8);

    /// @notice Returns the data of the latest round.
    /// @return roundId          Identifier of the round
    /// @return answer           Answer of the round, in `decimals()` decimal places
    /// @return startedAt        Time at which the round started
    /// @return updatedAt        Time at which the answer was last updated; zero if the round is incomplete
    /// @return answeredInRound  Deprecated; round in which the answer was computed
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
