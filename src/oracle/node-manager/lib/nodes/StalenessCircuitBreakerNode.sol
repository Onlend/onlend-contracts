// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {NodeDefinition} from "../NodeDefinition.sol";
import {NodeOutput} from "../NodeOutput.sol";

/// @title  StalenessCircuitBreakerNode
/// @notice Guards a parent node against stale prices, optionally falling back to a second parent.
library StalenessCircuitBreakerNode {
    /// @notice Thrown when the primary parent is stale and no fallback parent is configured.
    /// @param  nodeType   Type of the node that produced the primary output
    /// @param  timestamp  Timestamp of the stale primary output
    error StalenessToleranceExceeded(NodeDefinition.NodeType nodeType, uint256 timestamp);

    /// @notice Processes a STALENESS_CIRCUIT_BREAKER node and returns its output.
    /// @dev    Returns the primary parent when `block.timestamp - stalenessTolerance <= primary.timestamp`, otherwise
    ///         the fallback parent (without checking its staleness) if configured, otherwise reverts.
    /// @param  parentNodeOutputs  Primary parent output, optionally followed by the fallback parent output
    /// @param  parameters         ABI-encoded uint256 staleness tolerance in seconds
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        internal
        view
        returns (NodeOutput.Data memory)
    {
        uint256 stalenessTolerance = abi.decode(parameters, (uint256));

        /// @dev Cannot underflow: `isValid` rejects any tolerance above `block.timestamp` at registration, and
        ///      `block.timestamp` never decreases, so the stored tolerance stays at or below it.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp - stalenessTolerance <= parentNodeOutputs[0].timestamp) {
            return parentNodeOutputs[0];
        }

        if (parentNodeOutputs.length == 2) {
            return parentNodeOutputs[1];
        }

        revert StalenessToleranceExceeded(parentNodeOutputs[0].nodeType, parentNodeOutputs[0].timestamp);
    }

    /// @notice Returns true when the node definition is valid for a STALENESS_CIRCUIT_BREAKER node.
    /// @dev    The tolerance must not exceed `block.timestamp`, so processing can never underflow.
    /// @param  nodeDefinition  Node definition to validate
    function isValid(NodeDefinition.Data memory nodeDefinition) internal view returns (bool) {
        if (
            nodeDefinition.parents.length == 0 || nodeDefinition.parents.length > 2
                || nodeDefinition.parameters.length != 32
        ) return false;

        // forge-lint: disable-next-line(block-timestamp)
        return abi.decode(nodeDefinition.parameters, (uint256)) <= block.timestamp;
    }
}
