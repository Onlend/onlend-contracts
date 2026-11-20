// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {NodeDefinition} from "../NodeDefinition.sol";
import {NodeOutput} from "../NodeOutput.sol";
import {IAggregatorV3} from "../../interfaces/external/IAggregatorV3.sol";

/// @title  AggregatorV3Node
/// @notice Processes a price feed node that reads the latest round of an `AggregatorV3Interface` aggregator.
/// @dev    Freshness is not checked here: compose with a STALENESS_CIRCUIT_BREAKER node to bound the answer's age.
library AggregatorV3Node {
    /// @notice Decimal places of the output price.
    uint256 internal constant PRECISION = 18;

    /// @notice Thrown when the aggregator's latest answer has a zero `updatedAt`, such as an incomplete round.
    /// @param  aggregator  Address of the aggregator
    error ZeroUpdatedAt(address aggregator);

    /// @notice Processes an AGGREGATOR_V3 node and returns its output.
    /// @dev    Scales the latest answer to 18 decimal places, rounding down, and timestamps it with the round's
    ///         `updatedAt`. A zero answer is returned as a zero price, and a negative one reverts. A future `updatedAt`
    ///         is returned unchanged. Reverts from the aggregator are bubbled up. Feeds reporting more than 95 decimals
    ///         revert on overflow of the scaling factor.
    /// @param  parameters  ABI-encoded aggregator address
    function process(bytes memory parameters) internal view returns (NodeOutput.Data memory) {
        IAggregatorV3 aggregator = IAggregatorV3(abi.decode(parameters, (address)));

        (, int256 answer,, uint256 updatedAt,) = aggregator.latestRoundData();
        if (updatedAt == 0) revert ZeroUpdatedAt(address(aggregator));

        uint8 feedDecimals = aggregator.decimals();

        uint256 price = SafeCast.toUint256(answer);
        price = feedDecimals > PRECISION
            ? price / 10 ** (feedDecimals - PRECISION)
            : price * 10 ** (PRECISION - feedDecimals);

        return NodeOutput.Data(price, updatedAt, NodeDefinition.NodeType.AGGREGATOR_V3, 0, 0);
    }

    /// @notice Returns true when the node definition is valid for an AGGREGATOR_V3 node.
    /// @dev    Calls `latestRoundData()` and `decimals()` on the aggregator, so registration reverts if either call
    ///         reverts or returns data that does not decode. Neither call guarantees later behavior, nor that the
    ///         latest round is currently valid: `process` checks it on every read.
    /// @param  nodeDefinition  Node definition to validate
    function isValid(NodeDefinition.Data memory nodeDefinition) internal view returns (bool) {
        if (nodeDefinition.parents.length != 0 || nodeDefinition.parameters.length != 32) return false;

        IAggregatorV3 aggregator = IAggregatorV3(abi.decode(nodeDefinition.parameters, (address)));
        aggregator.latestRoundData();
        aggregator.decimals();

        return true;
    }
}
