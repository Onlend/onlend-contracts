// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IExternalNode} from "src/oracle/node-manager/interfaces/IExternalNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

/// @dev Configurable EXTERNAL node: returns a stored output, a stored validity, and can revert in each function.
contract MockExternalNode is IExternalNode {
    bool public shouldRevertOnProcess;
    bool public shouldRevertOnIsValid;
    bool public shouldRevertOnSupportsInterface;

    NodeOutput.Data private _output;
    bool private _isValid;

    error ProcessReverted();
    error IsValidReverted();
    error SupportsInterfaceReverted();

    /// @dev Seeds a valid node returning `price` at `timestamp`, typed EXTERNAL, with no additional params.
    constructor(uint256 price, uint256 timestamp) {
        _output = NodeOutput.Data(price, timestamp, NodeDefinition.NodeType.EXTERNAL, 0, 0);
        _isValid = true;
    }

    function setOutput(NodeOutput.Data memory output) external {
        _output = output;
    }

    function setIsValid(bool value) external {
        _isValid = value;
    }

    function setShouldRevertOnProcess(bool value) external {
        shouldRevertOnProcess = value;
    }

    function setShouldRevertOnIsValid(bool value) external {
        shouldRevertOnIsValid = value;
    }

    function setShouldRevertOnSupportsInterface(bool value) external {
        shouldRevertOnSupportsInterface = value;
    }

    function process(NodeOutput.Data[] memory, bytes memory) external view returns (NodeOutput.Data memory) {
        if (shouldRevertOnProcess) revert ProcessReverted();
        return _output;
    }

    function isValid(NodeDefinition.Data memory) external view returns (bool) {
        if (shouldRevertOnIsValid) revert IsValidReverted();
        return _isValid;
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        if (shouldRevertOnSupportsInterface) revert SupportsInterfaceReverted();
        return interfaceId == type(IExternalNode).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
