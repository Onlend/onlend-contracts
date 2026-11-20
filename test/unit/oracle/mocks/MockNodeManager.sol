// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {INodeManager} from "src/oracle/node-manager/interfaces/INodeManager.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

contract MockNodeManager is INodeManager {
    bool public supportsInterfaceOverride = true;
    bool public shouldRevertOnProcess;
    NodeOutput.Data private _output;

    error ProcessReverted();

    function setSupportsInterfaceOverride(bool value) external {
        supportsInterfaceOverride = value;
    }

    function setShouldRevertOnProcess(bool value) external {
        shouldRevertOnProcess = value;
    }

    function setOutput(NodeOutput.Data calldata output) external {
        _output = output;
    }

    function registerNode(NodeDefinition.NodeType, bytes calldata, bytes32[] calldata) external pure returns (bytes32) {
        return bytes32(0);
    }

    function isNodeRegistered(bytes32) external pure returns (bool) {
        return true;
    }

    function getNodeId(NodeDefinition.NodeType, bytes calldata, bytes32[] calldata) external pure returns (bytes32) {
        return bytes32(0);
    }

    function getNode(bytes32) external pure returns (NodeDefinition.Data memory node) {
        return node;
    }

    function process(bytes32) external view returns (NodeOutput.Data memory) {
        if (shouldRevertOnProcess) revert ProcessReverted();
        return _output;
    }

    function contractName() external pure returns (string memory name_) {
        return "MockNodeManager";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        if (!supportsInterfaceOverride) return false;
        return interfaceId == type(INodeManager).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
