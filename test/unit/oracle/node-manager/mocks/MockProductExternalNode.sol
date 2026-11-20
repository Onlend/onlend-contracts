// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IExternalNode} from "src/oracle/node-manager/interfaces/IExternalNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

/// @dev EXTERNAL node with exactly two parents: the price is their 18-decimal product, the timestamp the older one.
contract MockProductExternalNode is IExternalNode {
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory)
        external
        pure
        returns (NodeOutput.Data memory)
    {
        uint256 price = Math.mulDiv(parentNodeOutputs[0].price, parentNodeOutputs[1].price, 1e18);
        uint256 timestamp = Math.min(parentNodeOutputs[0].timestamp, parentNodeOutputs[1].timestamp);
        return NodeOutput.Data(price, timestamp, NodeDefinition.NodeType.EXTERNAL, 0, 0);
    }

    function isValid(NodeDefinition.Data memory nodeDefinition) external pure returns (bool) {
        return nodeDefinition.parents.length == 2;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IExternalNode).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
