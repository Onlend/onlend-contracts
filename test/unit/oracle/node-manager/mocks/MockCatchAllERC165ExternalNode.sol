// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IExternalNode} from "src/oracle/node-manager/interfaces/IExternalNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

/// @dev Valid EXTERNAL node whose `supportsInterface` claims every interface, including the invalid `0xffffffff`.
contract MockCatchAllERC165ExternalNode is IExternalNode {
    function process(NodeOutput.Data[] memory, bytes memory) external pure returns (NodeOutput.Data memory) {
        return NodeOutput.Data(1e18, 1, NodeDefinition.NodeType.EXTERNAL, 0, 0);
    }

    function isValid(NodeDefinition.Data memory) external pure returns (bool) {
        return true;
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}
