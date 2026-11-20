// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {NodeManager} from "src/oracle/node-manager/NodeManager.sol";
import {ReducerNode} from "src/oracle/node-manager/lib/nodes/ReducerNode.sol";
import {MockAggregatorV3} from "../../../mocks/MockAggregatorV3.sol";
import {NodeManagerHelper} from "./helpers/NodeManagerHelper.sol";
import {MockERC20Decimals} from "./mocks/MockERC20Decimals.sol";
import {MockERC4626Vault} from "./mocks/MockERC4626Vault.sol";
import {MockExternalNode} from "./mocks/MockExternalNode.sol";

contract NodeManagerFuzzTest is NodeManagerHelper {
    NodeManager internal implementation;
    NodeManager internal nodeManager;

    function setUp() public {
        implementation = new NodeManager();
        nodeManager = _deployNodeManager(new NodeDefinition.Data[](0));
    }

    // registerNode()

    function testFuzz_RegisterNode_StoresConstantNode(uint256 price) public {
        NodeDefinition.Data memory nodeDefinition = _constantNode(price);

        bytes32 nodeId =
            nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        NodeDefinition.Data memory stored = nodeManager.getNode(nodeId);
        assertEq(uint8(stored.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
        assertEq(stored.parameters, nodeDefinition.parameters);
        assertEq(stored.parents.length, 0);
    }

    function testFuzz_RegisterNode_ReturnsExpectedNodeId(uint256 price) public {
        NodeDefinition.Data memory nodeDefinition = _constantNode(price);
        bytes32 expectedId =
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        bytes32 returnedId =
            nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        assertEq(returnedId, expectedId);
    }

    // process()

    function testFuzz_Process_ConstantReturnsCorrectOutput(uint256 price, uint256 ts) public {
        ts = bound(ts, 1, type(uint32).max);
        bytes32 nodeId = _registerConstant(nodeManager, price);
        vm.warp(ts);

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, price);
        assertEq(output.timestamp, ts);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
        assertEq(output.additionalParam1, 0);
        assertEq(output.additionalParam2, 0);
    }

    function testFuzz_Process_StalenessReturnsPrimaryParent(uint256 price, uint256 tolerance, uint256 ts) public {
        ts = bound(ts, 1, type(uint32).max);
        vm.warp(ts);
        tolerance = bound(tolerance, 0, ts);
        bytes32 parentId = _registerConstant(nodeManager, price);
        bytes32 nodeId = _registerStaleness(nodeManager, tolerance, _parents(parentId));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, price);
        assertEq(output.timestamp, ts);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
    }

    function testFuzz_Process_StalenessReturnsFallbackWhenAggregatorIsStale(
        uint256 ts,
        uint256 tolerance,
        uint256 updatedAt,
        uint256 fallbackPrice
    ) public {
        ts = bound(ts, 2, type(uint32).max);
        vm.warp(ts);
        tolerance = bound(tolerance, 0, ts - 2);
        updatedAt = bound(updatedAt, 1, ts - tolerance - 1);
        bytes32 primaryId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 2000e8, updatedAt)));
        bytes32 fallbackId = _registerConstant(nodeManager, fallbackPrice);
        bytes32 nodeId = _registerStaleness(nodeManager, tolerance, _parents(primaryId, fallbackId));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, fallbackPrice);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
    }

    function testFuzz_Process_ReducerMinReturnsLowerParent(uint256 lower, uint256 higher) public {
        lower = bound(lower, 0, type(uint256).max - 1);
        higher = bound(higher, lower + 1, type(uint256).max);
        bytes32 higherId = _registerConstant(nodeManager, higher);
        bytes32 lowerId = _registerConstant(nodeManager, lower);
        bytes32 nodeId = _registerReducer(nodeManager, ReducerNode.Operation.MIN, _parents(higherId, lowerId));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, lower);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
    }

    function testFuzz_Process_PriceDeviationReturnsPrimaryForEqualPrices(uint256 price, uint256 tolerance) public {
        price = bound(price, 1, type(uint256).max);
        bytes32 parentId = _registerConstant(nodeManager, price);
        bytes32 nodeId = _registerPriceDeviation(nodeManager, tolerance, _parents(parentId, parentId));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, price);
    }

    function testFuzz_Process_AggregatorV3PreservesWholeUnits(uint256 units, uint8 feedDecimals, uint256 updatedAt)
        public
    {
        feedDecimals = uint8(bound(feedDecimals, 0, 76));
        units = bound(units, 0, Math.min(type(uint256).max / 1e18, uint256(type(int256).max) / 10 ** feedDecimals));
        updatedAt = bound(updatedAt, 1, type(uint256).max);
        MockAggregatorV3 aggregator =
            new MockAggregatorV3(feedDecimals, SafeCast.toInt256(units * 10 ** feedDecimals), updatedAt);
        bytes32 nodeId = _registerAggregatorV3(nodeManager, address(aggregator));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, units * 1e18);
        assertEq(output.timestamp, updatedAt);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.AGGREGATOR_V3));
    }

    function testFuzz_Process_VaultSharePricePreservesWholeUnits(
        uint256 parentPrice,
        uint256 units,
        uint8 shareDecimals,
        uint8 assetDecimals
    ) public {
        parentPrice = bound(parentPrice, 0, 1e36);
        shareDecimals = uint8(bound(shareDecimals, 0, 77));
        assetDecimals = uint8(bound(assetDecimals, 0, 77));
        units = bound(units, 1, Math.min(1e6, type(uint256).max / 10 ** assetDecimals));
        MockERC4626Vault vault = new MockERC4626Vault(
            address(new MockERC20Decimals(assetDecimals)), shareDecimals, units * 10 ** assetDecimals
        );
        bytes32 parentId = _registerConstant(nodeManager, parentPrice);
        bytes32 nodeId = _registerVaultSharePrice(nodeManager, address(vault), _parents(parentId));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, parentPrice * units);
        assertEq(output.timestamp, block.timestamp);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.VAULT_SHARE_PRICE));
    }

    function testFuzz_Process_SequencerUptimeReturnsParentOutputOnceGracePeriodIsOver(
        uint256 price,
        uint256 gracePeriod,
        uint256 startedAt,
        uint256 ts
    ) public {
        ts = bound(ts, 1, type(uint32).max);
        gracePeriod = bound(gracePeriod, 0, ts);
        startedAt = bound(startedAt, 0, ts - gracePeriod);
        bytes32 parentId = _registerConstant(nodeManager, price);
        MockAggregatorV3 feed = new MockAggregatorV3(0, 0, startedAt);
        bytes32 nodeId = _registerSequencerUptime(nodeManager, address(feed), gracePeriod, _parents(parentId));
        vm.warp(ts);

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, price);
        assertEq(output.timestamp, ts);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
    }

    function testFuzz_Process_ExternalReturnsExternalOutput(uint256 price, uint256 timestamp) public {
        bytes32 nodeId =
            _registerExternal(nodeManager, address(new MockExternalNode(price, timestamp)), new bytes32[](0));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, price);
        assertEq(output.timestamp, timestamp);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.EXTERNAL));
    }

    // getNodeId()

    function testFuzz_GetNodeId_DifferentPricesDifferentIds(uint256 a, uint256 b) public view {
        vm.assume(a != b);
        NodeDefinition.Data memory nodeDefinitionA = _constantNode(a);
        NodeDefinition.Data memory nodeDefinitionB = _constantNode(b);

        assertNotEq(
            nodeManager.getNodeId(nodeDefinitionA.nodeType, nodeDefinitionA.parameters, nodeDefinitionA.parents),
            nodeManager.getNodeId(nodeDefinitionB.nodeType, nodeDefinitionB.parameters, nodeDefinitionB.parents)
        );
    }

    function testFuzz_GetNodeId_DeterministicAcrossCallers(uint256 price, address caller) public {
        NodeDefinition.Data memory nodeDefinition = _constantNode(price);
        bytes32 idBefore =
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        vm.prank(caller);
        bytes32 idAfter =
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        assertEq(idBefore, idAfter);
    }

    function _deployNodeManager(NodeDefinition.Data[] memory nodes) internal returns (NodeManager instance) {
        instance = _clone();
        instance.initialize(nodes);
    }

    function _clone() internal returns (NodeManager) {
        return NodeManager(Clones.clone(address(implementation)));
    }
}
