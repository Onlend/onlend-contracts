// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title  NodeDefinition
/// @notice Diamond-storage backed registry of oracle feed node definitions.
library NodeDefinition {
    /// @notice Identifies the processing logic applied to a node.
    /// @dev    NONE is the zero-value sentinel used to detect unregistered nodes.
    enum NodeType {
        NONE,
        CONSTANT,
        STALENESS_CIRCUIT_BREAKER,
        REDUCER,
        PRICE_DEVIATION_CIRCUIT_BREAKER,
        AGGREGATOR_V3,
        VAULT_SHARE_PRICE,
        SEQUENCER_UPTIME,
        EXTERNAL
    }

    /// @notice Immutable definition of a node stored in the registry.
    /// @param  nodeType    Processing logic variant.
    /// @param  parameters  ABI-encoded parameters consumed by the node processor.
    /// @param  parents     Ordered list of parent node IDs whose outputs feed into this node.
    struct Data {
        NodeType nodeType;
        bytes parameters;
        bytes32[] parents;
    }

    /// @notice Registers a new node for a given node definition. The resulting node is a function of the definition.
    /// @param  nodeDefinition  Definition of the node to register
    /// @return node            Storage reference to the newly registered node
    /// @return id              Deterministic identifier derived from the definition
    function create(Data memory nodeDefinition) internal returns (Data storage node, bytes32 id) {
        id = getId(nodeDefinition);

        node = load(id);

        node.nodeType = nodeDefinition.nodeType;
        node.parameters = nodeDefinition.parameters;
        node.parents = nodeDefinition.parents;
    }

    /// @notice Returns the node stored at the specified node ID.
    /// @param  id    Node identifier
    /// @return node  Storage reference to the node definition
    function load(bytes32 id) internal pure returns (Data storage node) {
        bytes32 s = keccak256(abi.encode("onlend.oracle.Node", id));
        assembly {
            node.slot := s
        }
    }

    /// @notice Returns a node ID based on its definition.
    /// @param  nodeDefinition  Node definition
    /// @return id              Deterministic identifier derived from the definition
    function getId(Data memory nodeDefinition) internal pure returns (bytes32 id) {
        return keccak256(abi.encode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents));
    }
}
