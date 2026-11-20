// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {NodeDefinition} from "../NodeDefinition.sol";
import {NodeOutput} from "../NodeOutput.sol";

/// @title  ConstantNode
/// @notice Processes a constant price node that always returns a fixed value.
library ConstantNode {
    /// @notice Processes a CONSTANT node and returns its output.
    /// @param  parameters  ABI-encoded uint256 price
    function process(bytes memory parameters) internal view returns (NodeOutput.Data memory) {
        return
            NodeOutput.Data(abi.decode(parameters, (uint256)), block.timestamp, NodeDefinition.NodeType.CONSTANT, 0, 0);
    }

    /// @notice Returns true when the node definition is valid for a CONSTANT node.
    /// @param  nodeDefinition  Node definition to validate
    function isValid(NodeDefinition.Data memory nodeDefinition) internal pure returns (bool) {
        return (nodeDefinition.parents.length == 0 && nodeDefinition.parameters.length == 32);
    }
}
