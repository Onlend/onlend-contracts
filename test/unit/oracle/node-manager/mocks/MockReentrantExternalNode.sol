// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IExternalNode} from "src/oracle/node-manager/interfaces/IExternalNode.sol";
import {INodeManager} from "src/oracle/node-manager/interfaces/INodeManager.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

/// @dev Declares a state-changing `isValid` with the EXTERNAL node selector that re-enters `registerNode` once with the
///      definition it validates and accepts it on re-entry, so it can only succeed when called without STATICCALL.
contract MockReentrantExternalNode {
    INodeManager private immutable _NODE_MANAGER;

    bool private _entered;

    constructor(INodeManager nodeManager_) {
        _NODE_MANAGER = nodeManager_;
    }

    function process(NodeOutput.Data[] memory, bytes memory) external pure returns (NodeOutput.Data memory) {
        return NodeOutput.Data(1e18, 1, NodeDefinition.NodeType.EXTERNAL, 0, 0);
    }

    function isValid(NodeDefinition.Data memory nodeDefinition) external returns (bool) {
        if (_entered) return true;
        _entered = true;
        _NODE_MANAGER.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
        _entered = false;
        return true;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IExternalNode).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
