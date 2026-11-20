// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test} from "forge-std/Test.sol";

import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeManager} from "src/oracle/node-manager/NodeManager.sol";
import {ReducerNode} from "src/oracle/node-manager/lib/nodes/ReducerNode.sol";
import {MockAggregatorV3} from "../../../mocks/MockAggregatorV3.sol";
import {NodeManagerHelper} from "./helpers/NodeManagerHelper.sol";
import {MockERC20Decimals} from "./mocks/MockERC20Decimals.sol";
import {MockERC4626Vault} from "./mocks/MockERC4626Vault.sol";
import {MockExternalNode} from "./mocks/MockExternalNode.sol";

/// @notice Stateful handler — exposes registerNode actions and tracks registered IDs.
// forge-lint: disable-next-line(multi-contract-file)
contract NodeManagerHandler is NodeManagerHelper {
    NodeManager public nodeManager;

    bytes32[] public registeredIds;

    constructor(NodeManager _nodeManager) {
        nodeManager = _nodeManager;
    }

    function registerConstantNode(uint256 price) external {
        NodeDefinition.Data memory nodeDefinition = _constantNode(price);
        bytes32 nodeId =
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        if (nodeManager.isNodeRegistered(nodeId)) return;

        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
        registeredIds.push(nodeId);
    }

    function registerStalenessNode(uint256 price, uint256 tolerance) external {
        tolerance = bound(tolerance, 0, block.timestamp);
        bytes32 parentId = _registerConstantIfNew(price);

        NodeDefinition.Data memory nodeDefinition = _stalenessNode(tolerance, _parents(parentId));
        bytes32 nodeId =
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        if (nodeManager.isNodeRegistered(nodeId)) return;

        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
        registeredIds.push(nodeId);
    }

    /// @dev Prices are bounded to non-zero values up to 1e36 so every operation, including MUL_DECIMAL and
    ///      DIV_DECIMAL, stays processable.
    function registerReducerNode(uint256 firstPrice, uint256 secondPrice, uint256 operation) external {
        bytes32 firstId = _registerConstantIfNew(bound(firstPrice, 1, 1e36));
        bytes32 secondId = _registerConstantIfNew(bound(secondPrice, 1, 1e36));
        operation = bound(operation, 0, uint256(type(ReducerNode.Operation).max));

        NodeDefinition.Data memory nodeDefinition =
            _reducerNode(ReducerNode.Operation(operation), _parents(firstId, secondId));
        bytes32 nodeId =
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        if (nodeManager.isNodeRegistered(nodeId)) return;

        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
        registeredIds.push(nodeId);
    }

    /// @dev A fallback parent is always set and prices are bounded up to 1e36, so the node stays processable.
    function registerPriceDeviationNode(
        uint256 primaryPrice,
        uint256 comparisonPrice,
        uint256 fallbackPrice,
        uint256 tolerance
    ) external {
        bytes32 primaryId = _registerConstantIfNew(bound(primaryPrice, 0, 1e36));
        bytes32 comparisonId = _registerConstantIfNew(bound(comparisonPrice, 0, 1e36));
        bytes32 fallbackId = _registerConstantIfNew(fallbackPrice);

        NodeDefinition.Data memory nodeDefinition =
            _priceDeviationNode(tolerance, _parents(primaryId, comparisonId, fallbackId));
        bytes32 nodeId =
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        if (nodeManager.isNodeRegistered(nodeId)) return;

        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
        registeredIds.push(nodeId);
    }

    /// @dev Bounds keep the node processable; each call deploys a fresh aggregator, so the node is never a duplicate.
    function registerAggregatorV3Node(uint256 answer, uint8 feedDecimals, uint256 updatedAt) external {
        feedDecimals = uint8(bound(feedDecimals, 0, 95));
        answer = bound(answer, 0, type(uint256).max / 1e18);
        updatedAt = bound(updatedAt, 1, type(uint256).max);
        MockAggregatorV3 aggregator = new MockAggregatorV3(feedDecimals, SafeCast.toInt256(answer), updatedAt);

        bytes32 nodeId = _registerAggregatorV3(nodeManager, address(aggregator));
        registeredIds.push(nodeId);
    }

    /// @dev Decimals are bounded so `10 ** decimals` fits `uint256`, and the parent price and rate up to 1e36, so the
    ///      node stays processable; each call deploys a fresh vault, so the node is never a duplicate.
    function registerVaultSharePriceNode(uint256 price, uint8 shareDecimals, uint8 assetDecimals, uint256 rate)
        external
    {
        bytes32 parentId = _registerConstantIfNew(bound(price, 0, 1e36));
        shareDecimals = uint8(bound(shareDecimals, 0, 77));
        assetDecimals = uint8(bound(assetDecimals, 0, 77));
        rate = bound(rate, 0, 1e36);
        MockERC4626Vault vault =
            new MockERC4626Vault(address(new MockERC20Decimals(assetDecimals)), shareDecimals, rate);

        bytes32 nodeId = _registerVaultSharePrice(nodeManager, address(vault), _parents(parentId));
        registeredIds.push(nodeId);
    }

    /// @dev The feed always reports the sequencer as up, with a grace period already over, so the node stays
    ///      processable as time moves forward; each call deploys a fresh feed, so the node is never a duplicate.
    function registerSequencerUptimeNode(uint256 price, uint256 gracePeriod, uint256 startedAt) external {
        bytes32 parentId = _registerConstantIfNew(price);
        gracePeriod = bound(gracePeriod, 0, block.timestamp);
        startedAt = bound(startedAt, 0, block.timestamp - gracePeriod);
        MockAggregatorV3 feed = new MockAggregatorV3(0, 0, startedAt);

        bytes32 nodeId = _registerSequencerUptime(nodeManager, address(feed), gracePeriod, _parents(parentId));
        registeredIds.push(nodeId);
    }

    /// @dev The mock never reverts on `process`, whatever its price and timestamp; each call deploys a fresh external
    ///      node, so the node is never a duplicate.
    function registerExternalNode(uint256 price, uint256 timestamp) external {
        MockExternalNode externalNode = new MockExternalNode(price, timestamp);

        bytes32 nodeId = _registerExternal(nodeManager, address(externalNode), new bytes32[](0));
        registeredIds.push(nodeId);
    }

    function registeredCount() external view returns (uint256) {
        return registeredIds.length;
    }

    function _registerConstantIfNew(uint256 price) internal returns (bytes32 nodeId) {
        NodeDefinition.Data memory nodeDefinition = _constantNode(price);
        nodeId = nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
        if (nodeManager.isNodeRegistered(nodeId)) return nodeId;

        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
        registeredIds.push(nodeId);
    }
}

// forge-lint: disable-next-line(multi-contract-file)
contract NodeManagerInvariantsTest is Test {
    NodeManager implementation;
    NodeManager nodeManager;
    NodeManagerHandler handler;

    function setUp() public {
        implementation = new NodeManager();
        nodeManager = NodeManager(Clones.clone(address(implementation)));
        nodeManager.initialize(new NodeDefinition.Data[](0));
        handler = new NodeManagerHandler(nodeManager);

        targetContract(address(handler));
    }

    /// Every node tracked by the handler must be processable without revert.
    function invariant_RegisteredNodesAreAlwaysProcessable() public view {
        uint256 count = handler.registeredCount();
        for (uint256 i = 0; i < count; i++) {
            nodeManager.process(handler.registeredIds(i));
        }
    }

    /// Every node tracked by the handler must be reported as registered.
    function invariant_IsNodeRegisteredConsistentWithRegistry() public view {
        uint256 count = handler.registeredCount();
        for (uint256 i = 0; i < count; i++) {
            assertTrue(nodeManager.isNodeRegistered(handler.registeredIds(i)));
        }
    }

    /// Re-hashing stored node data must reproduce the original node ID.
    function invariant_NodeIdRoundtrips() public view {
        uint256 count = handler.registeredCount();
        for (uint256 i = 0; i < count; i++) {
            bytes32 nodeId = handler.registeredIds(i);
            NodeDefinition.Data memory nodeDefinition = nodeManager.getNode(nodeId);
            assertEq(
                nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents),
                nodeId
            );
        }
    }
}
