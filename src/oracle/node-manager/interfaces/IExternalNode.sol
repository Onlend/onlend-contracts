// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {NodeDefinition} from "../lib/NodeDefinition.sol";
import {NodeOutput} from "../lib/NodeOutput.sol";

/// @title  IExternalNode
/// @notice Pricing logic plugged into the NodeManager as an EXTERNAL node.
/// @dev    An EXTERNAL node's parameters start with the ABI-encoded address of the implementing contract, optionally
///         followed by custom bytes; the full parameters are passed to both functions. Implementations must return true
///         from `supportsInterface` for `IExternalNode`.
interface IExternalNode is IERC165 {
    /// @notice Processes the node and returns its output.
    /// @dev    Called with STATICCALL on every read. The returned `nodeType` is replaced with EXTERNAL by the caller.
    /// @param  parentNodeOutputs  Outputs of the node's parents, in parent order
    /// @param  parameters         Full node parameters, including the leading address word
    /// @return                    Output of the node
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        external
        view
        returns (NodeOutput.Data memory);

    /// @notice Returns true when the node definition is valid for this external node.
    /// @dev    Called once, at registration, with STATICCALL, so it cannot re-enter `registerNode` or write state. Must
    ///         check parent count and shape; the NodeManager only checks that parents are registered.
    /// @param  nodeDefinition  Node definition to validate, with full parameters and parents
    /// @return                 True if valid, false otherwise
    function isValid(NodeDefinition.Data memory nodeDefinition) external view returns (bool);
}
