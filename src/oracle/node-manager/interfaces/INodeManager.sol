// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {NodeDefinition} from "../lib/NodeDefinition.sol";
import {NodeOutput} from "../lib/NodeOutput.sol";
import {IVersioned} from "../../../interfaces/IVersioned.sol";

/// @title  INodeManager
/// @notice Permissionless registry for oracle feed nodes that can be composed into a processing graph.
interface INodeManager is IERC165, IVersioned {
    /// @notice Emitted when a new node is registered.
    /// @param  nodeId      Unique identifier of the registered node
    /// @param  nodeType    Type of the node
    /// @param  parameters  Encoded parameters for the node
    /// @param  parents     Parent node IDs this node depends on
    event NodeRegistered(bytes32 indexed nodeId, NodeDefinition.NodeType nodeType, bytes parameters, bytes32[] parents);

    /// @notice Thrown when attempting to register a node that is already registered.
    /// @param  nodeId  ID of the already-registered node
    error NodeAlreadyRegistered(bytes32 nodeId);

    /// @notice Thrown when referencing a node that has not been registered.
    /// @param  nodeId  ID of the unregistered node
    error NodeNotRegistered(bytes32 nodeId);

    /// @notice Thrown when the node definition is invalid for its type.
    /// @param  nodeDefinition  The invalid node definition
    error InvalidNodeDefinition(NodeDefinition.Data nodeDefinition);

    /// @notice Thrown when processing a registered node whose type has no processing logic.
    /// @param  nodeId  ID of the unprocessable node
    error UnprocessableNode(bytes32 nodeId);

    /// @notice Registers a new node with the given definition.
    /// @param  nodeType    Type of the node
    /// @param  parameters  Encoded parameters for the node
    /// @param  parents     Parent node IDs this node depends on
    /// @return nodeId      Unique identifier for the registered node
    function registerNode(NodeDefinition.NodeType nodeType, bytes calldata parameters, bytes32[] calldata parents)
        external
        returns (bytes32 nodeId);

    /// @notice Returns whether a node with the given ID is registered.
    /// @param  nodeId  Node identifier to query
    /// @return         True if registered, false otherwise
    function isNodeRegistered(bytes32 nodeId) external view returns (bool);

    /// @notice Returns the stored definition for a registered node.
    /// @param  nodeId  Node identifier to query
    /// @return node    Node definition (type, parameters, parents)
    function getNode(bytes32 nodeId) external view returns (NodeDefinition.Data memory node);

    /// @notice Processes a registered node and returns its output, recursively processing parents first.
    /// @param  nodeId  Node identifier to process
    /// @return node    Price, timestamp, node type, and additional params
    function process(bytes32 nodeId) external view returns (NodeOutput.Data memory node);

    /// @notice Computes the node ID for a given node definition without registering.
    /// @param  nodeType    Type of the node
    /// @param  parameters  Encoded parameters for the node
    /// @param  parents     Parent node IDs this node depends on
    /// @return nodeId      Deterministic identifier derived from the node data
    function getNodeId(NodeDefinition.NodeType nodeType, bytes calldata parameters, bytes32[] calldata parents)
        external
        pure
        returns (bytes32 nodeId);
}
