// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {NodeDefinition} from "../NodeDefinition.sol";
import {NodeOutput} from "../NodeOutput.sol";
import {IExternalNode} from "../../interfaces/IExternalNode.sol";

/// @title  ExternalNode
/// @notice Processes a node whose pricing logic lives in an external contract implementing `IExternalNode`.
/// @dev    Parameters are the ABI-encoded external contract address, optionally followed by custom bytes; the full
///         parameters and the processed parent outputs are passed through unchanged.
///
///         Security considerations, all on the operator choosing the node:
///         - Mutable logic: the node ID commits to the external contract's address, not its code or state. An
///           upgradeable or owner-controlled contract can change prices, or start reverting, after registration, and
///           its validity is only checked once, at registration. Only use contracts whose logic and controllers are
///           trusted as much as the node itself.
///         - Hidden inputs: the external contract may read any on-chain state, including other nodes through the
///           NodeManager, so its dependencies are not limited to its parents.
///         - Gas and return data: `process` is a STATICCALL forwarding all available gas, and a revert's data is
///           bubbled up in full, so a hostile contract can make reads expensive or fail. Successful return data is
///           decoded only up to the output's 160 bytes.
library ExternalNode {
    /// @notice Processes an EXTERNAL node and returns its output.
    /// @dev    The returned `nodeType` is replaced with EXTERNAL, so the external contract cannot report itself as
    ///         another node type; the price, timestamp and additional params are returned unchanged. Reverts from the
    ///         external contract are bubbled up, and return data that does not decode as an output reverts.
    /// @param  parentNodeOutputs  Outputs of the node's parents, in parent order
    /// @param  parameters         ABI-encoded external contract address, optionally followed by custom bytes
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        internal
        view
        returns (NodeOutput.Data memory nodeOutput)
    {
        IExternalNode externalNode = IExternalNode(abi.decode(parameters, (address)));

        nodeOutput = externalNode.process(parentNodeOutputs, parameters);
        nodeOutput.nodeType = NodeDefinition.NodeType.EXTERNAL;
    }

    /// @notice Returns true when the node definition is valid for an EXTERNAL node.
    /// @dev    Requires parameters of at least 32 bytes, the external contract to return true from `supportsInterface`
    ///         for `IExternalNode`, and its `isValid` to return true for the definition. Parent count and shape are
    ///         left to the external contract. `isValid` is called with STATICCALL, so registration reverts if it
    ///         reverts, writes state, or returns data that does not decode as a bool.
    /// @param  nodeDefinition  Node definition to validate
    function isValid(NodeDefinition.Data memory nodeDefinition) internal view returns (bool) {
        if (nodeDefinition.parameters.length < 32) return false;

        address externalNode = abi.decode(nodeDefinition.parameters, (address));

        return ERC165Checker.supportsInterface(externalNode, type(IExternalNode).interfaceId)
            && IExternalNode(externalNode).isValid(nodeDefinition);
    }
}
