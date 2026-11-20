// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {NodeDefinition} from "../NodeDefinition.sol";
import {NodeOutput} from "../NodeOutput.sol";
import {MathUtils} from "../../../../lib/MathUtils.sol";

/// @title  ReducerNode
/// @notice Reduces the outputs of two or more parent nodes into a single output.
/// @dev    Selection operations (RECENT, MIN, MAX, odd-length MEDIAN) return the selected parent output unchanged.
///         Computed operations (MEAN, even-length MEDIAN, MUL_DECIMAL, DIV_DECIMAL) return a REDUCER output whose
///         timestamp is the oldest timestamp among the parents it is computed from (the two middle ones for MEDIAN), so
///         a downstream staleness check sees the stalest input.
library ReducerNode {
    /// @notice Reduction applied to the parent outputs.
    /// @dev    RECENT       Parent output with the latest timestamp; the first one on ties.
    ///         MIN          Parent output with the lowest price; the first one on ties.
    ///         MAX          Parent output with the highest price; the first one on ties.
    ///         MEAN         Arithmetic mean of the parent prices, rounded down.
    ///         MEDIAN       Median parent output; the mean of the two middle prices for an even number of parents.
    ///         MUL_DECIMAL  Product of the parent prices as 18 decimal place values, rounded down at each step.
    ///         DIV_DECIMAL  First parent price divided by each following one as 18 decimal place values, rounded
    ///                      down at each step.
    enum Operation {
        RECENT,
        MIN,
        MAX,
        MEAN,
        MEDIAN,
        MUL_DECIMAL,
        DIV_DECIMAL
    }

    /// @notice Thrown when the operation has no reduction logic.
    /// @param  operation  The unsupported operation
    error UnsupportedOperation(Operation operation);

    /// @notice Thrown when a DIV_DECIMAL divisor parent has a zero price.
    /// @param  parentIndex  Index of the parent whose price is zero
    error DivisionByZero(uint256 parentIndex);

    /// @notice Processes a REDUCER node and returns its output.
    /// @param  parentNodeOutputs  Outputs of the parent nodes, in parent order
    /// @param  parameters         ABI-encoded Operation
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        internal
        pure
        returns (NodeOutput.Data memory)
    {
        Operation operation = abi.decode(parameters, (Operation));

        if (operation == Operation.RECENT) return _recent(parentNodeOutputs);
        if (operation == Operation.MIN) return _min(parentNodeOutputs);
        if (operation == Operation.MAX) return _max(parentNodeOutputs);
        if (operation == Operation.MEAN) return _mean(parentNodeOutputs);
        if (operation == Operation.MEDIAN) return _median(parentNodeOutputs);
        if (operation == Operation.MUL_DECIMAL) return _mulDecimal(parentNodeOutputs);
        if (operation == Operation.DIV_DECIMAL) return _divDecimal(parentNodeOutputs);
        revert UnsupportedOperation(operation);
    }

    /// @notice Returns true when the node definition is valid for a REDUCER node.
    /// @param  nodeDefinition  Node definition to validate
    function isValid(NodeDefinition.Data memory nodeDefinition) internal pure returns (bool) {
        if (nodeDefinition.parents.length < 2 || nodeDefinition.parameters.length != 32) return false;

        /// @dev Decoded as uint256 so an out-of-range operation returns false instead of reverting
        return abi.decode(nodeDefinition.parameters, (uint256)) <= uint256(type(Operation).max);
    }

    /// @notice Returns the parent output with the latest timestamp; the earliest parent on ties.
    function _recent(NodeOutput.Data[] memory parentNodeOutputs) private pure returns (NodeOutput.Data memory recent) {
        recent = parentNodeOutputs[0];
        for (uint256 i = 1; i < parentNodeOutputs.length; ++i) {
            if (parentNodeOutputs[i].timestamp > recent.timestamp) recent = parentNodeOutputs[i];
        }
    }

    /// @notice Returns the parent output with the lowest price; the earliest parent on ties.
    function _min(NodeOutput.Data[] memory parentNodeOutputs) private pure returns (NodeOutput.Data memory min) {
        min = parentNodeOutputs[0];
        for (uint256 i = 1; i < parentNodeOutputs.length; ++i) {
            if (parentNodeOutputs[i].price < min.price) min = parentNodeOutputs[i];
        }
    }

    /// @notice Returns the parent output with the highest price; the earliest parent on ties.
    function _max(NodeOutput.Data[] memory parentNodeOutputs) private pure returns (NodeOutput.Data memory max) {
        max = parentNodeOutputs[0];
        for (uint256 i = 1; i < parentNodeOutputs.length; ++i) {
            if (parentNodeOutputs[i].price > max.price) max = parentNodeOutputs[i];
        }
    }

    /// @notice Returns the mean of the parent prices, rounded down, timestamped with the oldest parent timestamp.
    function _mean(NodeOutput.Data[] memory parentNodeOutputs) private pure returns (NodeOutput.Data memory) {
        uint256 sum = parentNodeOutputs[0].price;
        uint256 timestamp = parentNodeOutputs[0].timestamp;
        for (uint256 i = 1; i < parentNodeOutputs.length; ++i) {
            sum += parentNodeOutputs[i].price;
            timestamp = Math.min(timestamp, parentNodeOutputs[i].timestamp);
        }
        return NodeOutput.Data(sum / parentNodeOutputs.length, timestamp, NodeDefinition.NodeType.REDUCER, 0, 0);
    }

    /// @notice Returns the median parent output, or the mean of the two middle outputs for an even count.
    /// @dev    Sorts a copy by price with insertion sort, which is cheapest for the handful of parents a node has.
    function _median(NodeOutput.Data[] memory parentNodeOutputs) private pure returns (NodeOutput.Data memory) {
        uint256 length = parentNodeOutputs.length;
        NodeOutput.Data[] memory sorted = new NodeOutput.Data[](length);
        for (uint256 i = 0; i < length; ++i) {
            NodeOutput.Data memory output = parentNodeOutputs[i];
            uint256 j = i;
            while (j > 0 && sorted[j - 1].price > output.price) {
                sorted[j] = sorted[j - 1];
                --j;
            }
            sorted[j] = output;
        }

        if (length % 2 == 1) return sorted[length / 2];

        NodeOutput.Data[] memory middle = new NodeOutput.Data[](2);
        middle[0] = sorted[length / 2 - 1];
        middle[1] = sorted[length / 2];
        return _mean(middle);
    }

    /// @notice Returns the product of the parent prices as 18 decimal place values, timestamped with the oldest parent
    ///         timestamp.
    function _mulDecimal(NodeOutput.Data[] memory parentNodeOutputs) private pure returns (NodeOutput.Data memory) {
        uint256 price = parentNodeOutputs[0].price;
        uint256 timestamp = parentNodeOutputs[0].timestamp;
        for (uint256 i = 1; i < parentNodeOutputs.length; ++i) {
            price = Math.mulDiv(price, parentNodeOutputs[i].price, MathUtils.ONE_18_DP);
            timestamp = Math.min(timestamp, parentNodeOutputs[i].timestamp);
        }
        return NodeOutput.Data(price, timestamp, NodeDefinition.NodeType.REDUCER, 0, 0);
    }

    /// @notice Returns the first parent price divided by each following one as 18 decimal place values, timestamped
    ///         with the oldest parent timestamp.
    function _divDecimal(NodeOutput.Data[] memory parentNodeOutputs) private pure returns (NodeOutput.Data memory) {
        uint256 price = parentNodeOutputs[0].price;
        uint256 timestamp = parentNodeOutputs[0].timestamp;
        for (uint256 i = 1; i < parentNodeOutputs.length; ++i) {
            if (parentNodeOutputs[i].price == 0) revert DivisionByZero(i);
            price = Math.mulDiv(price, MathUtils.ONE_18_DP, parentNodeOutputs[i].price);
            timestamp = Math.min(timestamp, parentNodeOutputs[i].timestamp);
        }
        return NodeOutput.Data(price, timestamp, NodeDefinition.NodeType.REDUCER, 0, 0);
    }
}
