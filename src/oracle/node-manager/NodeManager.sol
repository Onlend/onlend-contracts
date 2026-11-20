// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {AggregatorV3Node} from "./lib/nodes/AggregatorV3Node.sol";
import {ConstantNode} from "./lib/nodes/ConstantNode.sol";
import {ExternalNode} from "./lib/nodes/ExternalNode.sol";
import {PriceDeviationCircuitBreakerNode} from "./lib/nodes/PriceDeviationCircuitBreakerNode.sol";
import {ReducerNode} from "./lib/nodes/ReducerNode.sol";
import {SequencerUptimeNode} from "./lib/nodes/SequencerUptimeNode.sol";
import {StalenessCircuitBreakerNode} from "./lib/nodes/StalenessCircuitBreakerNode.sol";
import {VaultSharePriceNode} from "./lib/nodes/VaultSharePriceNode.sol";
import {NodeDefinition} from "./lib/NodeDefinition.sol";
import {NodeOutput} from "./lib/NodeOutput.sol";
import {INodeManager} from "./interfaces/INodeManager.sol";
import {IVersioned} from "../../interfaces/IVersioned.sol";

/// @title  NodeManager
/// @notice Permissionless registry and processor for oracle feed nodes.
/// @dev    Implementation for EIP-1167 clones; initial nodes are registered via `initialize`.
contract NodeManager is INodeManager, Initializable {
    /// @notice Disables initialization on the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a clone by registering its initial node definitions.
    /// @dev Reverts atomically if any node definition cannot be registered.
    /// @param nodes Initial node definitions to register.
    function initialize(NodeDefinition.Data[] calldata nodes) external initializer {
        for (uint256 i; i < nodes.length; ++i) {
            _registerNode(nodes[i]);
        }
    }

    /// @inheritdoc INodeManager
    function registerNode(NodeDefinition.NodeType nodeType, bytes calldata parameters, bytes32[] calldata parents)
        external
        override
        returns (bytes32 nodeId)
    {
        NodeDefinition.Data memory nodeDefinition =
            NodeDefinition.Data({nodeType: nodeType, parameters: parameters, parents: parents});
        return _registerNode(nodeDefinition);
    }

    /// @inheritdoc INodeManager
    function isNodeRegistered(bytes32 nodeId) external view override returns (bool) {
        return _isNodeRegistered(nodeId);
    }

    /// @inheritdoc INodeManager
    function process(bytes32 nodeId) external view override returns (NodeOutput.Data memory node) {
        if (!_isNodeRegistered(nodeId)) revert NodeNotRegistered(nodeId);
        return _process(nodeId);
    }

    /// @inheritdoc INodeManager
    function getNodeId(NodeDefinition.NodeType nodeType, bytes calldata parameters, bytes32[] calldata parents)
        external
        pure
        override
        returns (bytes32 nodeId)
    {
        NodeDefinition.Data memory nodeDefinition =
            NodeDefinition.Data({parents: parents, nodeType: nodeType, parameters: parameters});

        return NodeDefinition.getId(nodeDefinition);
    }

    /// @inheritdoc INodeManager
    function getNode(bytes32 nodeId) external pure override returns (NodeDefinition.Data memory node) {
        return NodeDefinition.load(nodeId);
    }

    /// @inheritdoc IVersioned
    function contractName() external pure override returns (string memory) {
        return "NodeManager";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure override returns (string memory) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override(IERC165) returns (bool) {
        return interfaceId == type(INodeManager).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Registers a new node.
    /// @param  nodeDefinition  The definition of the node to register.
    /// @return nodeId          The ID of the registered node.
    function _registerNode(NodeDefinition.Data memory nodeDefinition) internal returns (bytes32 nodeId) {
        /// @dev Get the ID of the node definition
        nodeId = NodeDefinition.getId(nodeDefinition);

        /// @dev Check if the node is already registered
        if (_isNodeRegistered(nodeId)) {
            revert NodeAlreadyRegistered(nodeId);
        }

        /// @dev Check if the node definition is valid
        if (!_isValidNodeDefinition(nodeDefinition)) {
            revert InvalidNodeDefinition(nodeDefinition);
        }

        /// @dev Check if each parent node is registered
        for (uint256 i; i < nodeDefinition.parents.length; ++i) {
            if (!_isNodeRegistered(nodeDefinition.parents[i])) {
                revert NodeNotRegistered(nodeDefinition.parents[i]);
            }
        }

        /// @dev Create the node saving the node definition in the storage and emit the NodeRegistered event
        (, nodeId) = NodeDefinition.create(nodeDefinition);
        emit NodeRegistered(nodeId, nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    /// @notice Processes a node.
    /// @param  nodeId  The ID of the node to process.
    /// @return node    The output of the processed node.
    function _process(bytes32 nodeId) internal view returns (NodeOutput.Data memory node) {
        /// @dev Load the node definition
        NodeDefinition.Data memory nodeDefinition = NodeDefinition.load(nodeId);

        /// @dev Process the node based on its type
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.CONSTANT) {
            return ConstantNode.process(nodeDefinition.parameters);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.STALENESS_CIRCUIT_BREAKER) {
            return StalenessCircuitBreakerNode.process(_processParents(nodeDefinition), nodeDefinition.parameters);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.REDUCER) {
            return ReducerNode.process(_processParents(nodeDefinition), nodeDefinition.parameters);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.PRICE_DEVIATION_CIRCUIT_BREAKER) {
            return PriceDeviationCircuitBreakerNode.process(_processParents(nodeDefinition), nodeDefinition.parameters);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.AGGREGATOR_V3) {
            return AggregatorV3Node.process(nodeDefinition.parameters);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.VAULT_SHARE_PRICE) {
            return VaultSharePriceNode.process(_processParents(nodeDefinition), nodeDefinition.parameters);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.SEQUENCER_UPTIME) {
            return SequencerUptimeNode.process(_processParents(nodeDefinition), nodeDefinition.parameters);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.EXTERNAL) {
            return ExternalNode.process(_processParents(nodeDefinition), nodeDefinition.parameters);
        }
        /// @dev If the node type is not recognized, revert
        revert UnprocessableNode(nodeId);
    }

    /// @notice Checks if a node is registered.
    /// @param  nodeId  The ID of the node to check.
    /// @return         A boolean indicating whether the node is registered.
    function _isNodeRegistered(bytes32 nodeId) internal view returns (bool) {
        /// @dev Load the node definition and check if its type is not NONE
        return NodeDefinition.load(nodeId).nodeType != NodeDefinition.NodeType.NONE;
    }

    /// @notice Checks if a node definition is valid.
    /// @param  nodeDefinition  The node definition to check.
    /// @return                 A boolean indicating whether the node definition is valid.
    function _isValidNodeDefinition(NodeDefinition.Data memory nodeDefinition) internal view returns (bool) {
        /// @dev Check the node type and call the corresponding isValid function
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.CONSTANT) {
            return ConstantNode.isValid(nodeDefinition);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.STALENESS_CIRCUIT_BREAKER) {
            return StalenessCircuitBreakerNode.isValid(nodeDefinition);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.REDUCER) {
            return ReducerNode.isValid(nodeDefinition);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.PRICE_DEVIATION_CIRCUIT_BREAKER) {
            return PriceDeviationCircuitBreakerNode.isValid(nodeDefinition);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.AGGREGATOR_V3) {
            return AggregatorV3Node.isValid(nodeDefinition);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.VAULT_SHARE_PRICE) {
            return VaultSharePriceNode.isValid(nodeDefinition);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.SEQUENCER_UPTIME) {
            return SequencerUptimeNode.isValid(nodeDefinition);
        }
        if (nodeDefinition.nodeType == NodeDefinition.NodeType.EXTERNAL) {
            return ExternalNode.isValid(nodeDefinition);
        }
        /// @dev If the node type is not recognized, return false
        return false;
    }

    /// @notice Processes the parent nodes of a node.
    /// @param  nodeDefinition     The definition of the node whose parents to process.
    /// @return parentNodeOutputs  The outputs of the processed parent nodes, in parent order.
    function _processParents(NodeDefinition.Data memory nodeDefinition)
        private
        view
        returns (NodeOutput.Data[] memory parentNodeOutputs)
    {
        parentNodeOutputs = new NodeOutput.Data[](nodeDefinition.parents.length);
        for (uint256 i; i < nodeDefinition.parents.length; ++i) {
            parentNodeOutputs[i] = _process(nodeDefinition.parents[i]);
        }
    }
}
