// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

/// @dev Implements the EXTERNAL node functions but not `supportsInterface`.
contract MockNoERC165ExternalNode {
    function process(NodeOutput.Data[] memory, bytes memory) external pure returns (NodeOutput.Data memory) {
        return NodeOutput.Data(1e18, 1, NodeDefinition.NodeType.EXTERNAL, 0, 0);
    }

    function isValid(NodeDefinition.Data memory) external pure returns (bool) {
        return true;
    }
}
