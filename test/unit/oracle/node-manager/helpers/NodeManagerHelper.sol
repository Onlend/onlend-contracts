// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeManager} from "src/oracle/node-manager/NodeManager.sol";
import {ReducerNode} from "src/oracle/node-manager/lib/nodes/ReducerNode.sol";

contract NodeManagerHelper is Test {
    function _constantNode(uint256 price) internal pure returns (NodeDefinition.Data memory) {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.CONSTANT, parameters: abi.encode(price), parents: new bytes32[](0)
        });
    }

    function _registerConstant(NodeManager nodeManager, uint256 price) internal returns (bytes32 nodeId) {
        NodeDefinition.Data memory nodeDefinition = _constantNode(price);
        return nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function _stalenessNode(uint256 stalenessTolerance, bytes32[] memory parents)
        internal
        pure
        returns (NodeDefinition.Data memory)
    {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.STALENESS_CIRCUIT_BREAKER,
            parameters: abi.encode(stalenessTolerance),
            parents: parents
        });
    }

    function _registerStaleness(NodeManager nodeManager, uint256 stalenessTolerance, bytes32[] memory parents)
        internal
        returns (bytes32 nodeId)
    {
        NodeDefinition.Data memory nodeDefinition = _stalenessNode(stalenessTolerance, parents);
        return nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function _reducerNode(ReducerNode.Operation operation, bytes32[] memory parents)
        internal
        pure
        returns (NodeDefinition.Data memory)
    {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.REDUCER, parameters: abi.encode(operation), parents: parents
        });
    }

    function _registerReducer(NodeManager nodeManager, ReducerNode.Operation operation, bytes32[] memory parents)
        internal
        returns (bytes32 nodeId)
    {
        NodeDefinition.Data memory nodeDefinition = _reducerNode(operation, parents);
        return nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function _priceDeviationNode(uint256 deviationTolerance, bytes32[] memory parents)
        internal
        pure
        returns (NodeDefinition.Data memory)
    {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.PRICE_DEVIATION_CIRCUIT_BREAKER,
            parameters: abi.encode(deviationTolerance),
            parents: parents
        });
    }

    function _registerPriceDeviation(NodeManager nodeManager, uint256 deviationTolerance, bytes32[] memory parents)
        internal
        returns (bytes32 nodeId)
    {
        NodeDefinition.Data memory nodeDefinition = _priceDeviationNode(deviationTolerance, parents);
        return nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function _aggregatorV3Node(address aggregator) internal pure returns (NodeDefinition.Data memory) {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.AGGREGATOR_V3,
            parameters: abi.encode(aggregator),
            parents: new bytes32[](0)
        });
    }

    function _registerAggregatorV3(NodeManager nodeManager, address aggregator) internal returns (bytes32 nodeId) {
        NodeDefinition.Data memory nodeDefinition = _aggregatorV3Node(aggregator);
        return nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function _vaultSharePriceNode(address vault, bytes32[] memory parents)
        internal
        pure
        returns (NodeDefinition.Data memory)
    {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.VAULT_SHARE_PRICE, parameters: abi.encode(vault), parents: parents
        });
    }

    function _registerVaultSharePrice(NodeManager nodeManager, address vault, bytes32[] memory parents)
        internal
        returns (bytes32 nodeId)
    {
        NodeDefinition.Data memory nodeDefinition = _vaultSharePriceNode(vault, parents);
        return nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function _sequencerUptimeNode(address sequencerUptimeFeed, uint256 gracePeriod, bytes32[] memory parents)
        internal
        pure
        returns (NodeDefinition.Data memory)
    {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.SEQUENCER_UPTIME,
            parameters: abi.encode(sequencerUptimeFeed, gracePeriod),
            parents: parents
        });
    }

    function _registerSequencerUptime(
        NodeManager nodeManager,
        address sequencerUptimeFeed,
        uint256 gracePeriod,
        bytes32[] memory parents
    ) internal returns (bytes32 nodeId) {
        NodeDefinition.Data memory nodeDefinition = _sequencerUptimeNode(sequencerUptimeFeed, gracePeriod, parents);
        return nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function _externalNode(address externalNode, bytes32[] memory parents)
        internal
        pure
        returns (NodeDefinition.Data memory)
    {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.EXTERNAL, parameters: abi.encode(externalNode), parents: parents
        });
    }

    function _registerExternal(NodeManager nodeManager, address externalNode, bytes32[] memory parents)
        internal
        returns (bytes32 nodeId)
    {
        NodeDefinition.Data memory nodeDefinition = _externalNode(externalNode, parents);
        return nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function _parents(bytes32 parent) internal pure returns (bytes32[] memory parents) {
        parents = new bytes32[](1);
        parents[0] = parent;
    }

    function _parents(bytes32 first, bytes32 second) internal pure returns (bytes32[] memory parents) {
        parents = new bytes32[](2);
        parents[0] = first;
        parents[1] = second;
    }

    function _parents(bytes32 first, bytes32 second, bytes32 third) internal pure returns (bytes32[] memory parents) {
        parents = new bytes32[](3);
        parents[0] = first;
        parents[1] = second;
        parents[2] = third;
    }
}
