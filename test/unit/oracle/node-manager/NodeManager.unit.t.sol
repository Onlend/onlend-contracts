// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {INodeManager} from "src/oracle/node-manager/interfaces/INodeManager.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {NodeManager} from "src/oracle/node-manager/NodeManager.sol";
import {PriceDeviationCircuitBreakerNode} from "src/oracle/node-manager/lib/nodes/PriceDeviationCircuitBreakerNode.sol";
import {ReducerNode} from "src/oracle/node-manager/lib/nodes/ReducerNode.sol";
import {SequencerUptimeNode} from "src/oracle/node-manager/lib/nodes/SequencerUptimeNode.sol";
import {StalenessCircuitBreakerNode} from "src/oracle/node-manager/lib/nodes/StalenessCircuitBreakerNode.sol";
import {MockAggregatorV3} from "../../../mocks/MockAggregatorV3.sol";
import {NodeManagerHelper} from "./helpers/NodeManagerHelper.sol";
import {MockERC20Decimals} from "./mocks/MockERC20Decimals.sol";
import {MockERC4626Vault} from "./mocks/MockERC4626Vault.sol";
import {MockExternalNode} from "./mocks/MockExternalNode.sol";
import {MockProductExternalNode} from "./mocks/MockProductExternalNode.sol";
import {MockReentrantExternalNode} from "./mocks/MockReentrantExternalNode.sol";

contract NodeManagerTest is NodeManagerHelper {
    NodeManager internal implementation;
    NodeManager internal nodeManager;

    function setUp() public {
        implementation = new NodeManager();
        nodeManager = _deployNodeManager(new NodeDefinition.Data[](0));
    }

    // initialize()

    function test_initialize_RegistersMultipleNodes() public {
        NodeDefinition.Data[] memory nodes = new NodeDefinition.Data[](2);
        nodes[0] = _constantNode(1e18);
        nodes[1] = _constantNode(2e18);

        NodeManager instance = _deployNodeManager(nodes);

        bytes32 firstNodeId = instance.getNodeId(nodes[0].nodeType, nodes[0].parameters, nodes[0].parents);
        bytes32 secondNodeId = instance.getNodeId(nodes[1].nodeType, nodes[1].parameters, nodes[1].parents);
        assertTrue(instance.isNodeRegistered(firstNodeId));
        assertTrue(instance.isNodeRegistered(secondNodeId));
    }

    function test_initialize_AllowsNoInitialNodes() public {
        NodeManager instance = _deployNodeManager(new NodeDefinition.Data[](0));
        NodeDefinition.Data memory nodeDefinition = _constantNode(1e18);
        bytes32 nodeId = instance.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        assertFalse(instance.isNodeRegistered(nodeId));
    }

    function test_initialize_RevertsAtomicallyWhenNodeDefinitionIsInvalid() public {
        NodeDefinition.Data[] memory nodes = new NodeDefinition.Data[](2);
        nodes[0] = _constantNode(1e18);
        nodes[1] =
            NodeDefinition.Data({nodeType: NodeDefinition.NodeType.NONE, parameters: "", parents: new bytes32[](0)});
        bytes32 firstNodeId = nodeManager.getNodeId(nodes[0].nodeType, nodes[0].parameters, nodes[0].parents);
        NodeManager instance = _clone();

        vm.expectRevert(abi.encodeWithSelector(INodeManager.InvalidNodeDefinition.selector, nodes[1]));
        instance.initialize(nodes);

        assertFalse(instance.isNodeRegistered(firstNodeId));
    }

    function test_initialize_RevertsAtomicallyWhenNodeIsDuplicated() public {
        NodeDefinition.Data[] memory nodes = new NodeDefinition.Data[](2);
        nodes[0] = _constantNode(1e18);
        nodes[1] = nodes[0];
        bytes32 nodeId = keccak256(abi.encode(nodes[0].nodeType, nodes[0].parameters, nodes[0].parents));
        NodeManager instance = _clone();

        vm.expectRevert(abi.encodeWithSelector(INodeManager.NodeAlreadyRegistered.selector, nodeId));
        instance.initialize(nodes);

        assertFalse(instance.isNodeRegistered(nodeId));
    }

    // registerNode()

    function test_RegisterNode_StoresNode() public {
        NodeDefinition.Data memory nodeDefinition = _constantNode(1e18);

        bytes32 id =
            nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        NodeDefinition.Data memory stored = nodeManager.getNode(id);
        assertEq(uint8(stored.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
        assertEq(stored.parameters, nodeDefinition.parameters);
        assertEq(stored.parents.length, 0);
    }

    function test_RegisterNode_ReturnsNodeId() public {
        NodeDefinition.Data memory nodeDefinition = _constantNode(1e18);
        bytes32 expectedId =
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        bytes32 returnedId =
            nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        assertEq(returnedId, expectedId);
    }

    function test_RegisterNode_EmitsNodeRegistered() public {
        NodeDefinition.Data memory nodeDefinition = _constantNode(1e18);
        bytes32 expectedId =
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        vm.expectEmit();
        emit INodeManager.NodeRegistered(
            expectedId, nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents
        );
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_StoresNodeWithParents() public {
        vm.warp(99_999);
        bytes32 parentId = _registerConstant(nodeManager, 1e18);
        NodeDefinition.Data memory nodeDefinition = _stalenessNode(100, _parents(parentId));

        bytes32 id =
            nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        NodeDefinition.Data memory stored = nodeManager.getNode(id);
        assertEq(uint8(stored.nodeType), uint8(NodeDefinition.NodeType.STALENESS_CIRCUIT_BREAKER));
        assertEq(stored.parameters, nodeDefinition.parameters);
        assertEq(stored.parents.length, 1);
        assertEq(stored.parents[0], parentId);
    }

    function test_RegisterNode_Revert_NoneType() public {
        NodeDefinition.Data memory nodeDefinition =
            NodeDefinition.Data({nodeType: NodeDefinition.NodeType.NONE, parameters: "", parents: new bytes32[](0)});

        vm.expectRevert(abi.encodeWithSelector(INodeManager.InvalidNodeDefinition.selector, nodeDefinition));
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_Revert_AlreadyRegistered() public {
        NodeDefinition.Data memory nodeDefinition = _constantNode(1e18);
        bytes32 nodeId =
            nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        vm.expectRevert(abi.encodeWithSelector(INodeManager.NodeAlreadyRegistered.selector, nodeId));
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_Revert_InvalidNodeDefinition() public {
        NodeDefinition.Data memory nodeDefinition = NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.CONSTANT,
            parameters: abi.encodePacked(uint128(1e18)),
            parents: new bytes32[](0)
        });

        vm.expectRevert(abi.encodeWithSelector(INodeManager.InvalidNodeDefinition.selector, nodeDefinition));
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_Revert_ParentNotRegistered() public {
        vm.warp(99_999);
        bytes32 registeredParentId = _registerConstant(nodeManager, 1e18);
        bytes32 unregisteredParentId = bytes32(uint256(0xdead));
        NodeDefinition.Data memory nodeDefinition =
            _stalenessNode(100, _parents(registeredParentId, unregisteredParentId));

        vm.expectRevert(abi.encodeWithSelector(INodeManager.NodeNotRegistered.selector, unregisteredParentId));
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_Revert_InvalidReducerDefinition() public {
        bytes32 parentId = _registerConstant(nodeManager, 1e18);
        NodeDefinition.Data memory nodeDefinition = _reducerNode(ReducerNode.Operation.MIN, _parents(parentId));

        vm.expectRevert(abi.encodeWithSelector(INodeManager.InvalidNodeDefinition.selector, nodeDefinition));
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_Revert_InvalidPriceDeviationDefinition() public {
        bytes32 parentId = _registerConstant(nodeManager, 1e18);
        NodeDefinition.Data memory nodeDefinition = _priceDeviationNode(0.01e18, _parents(parentId));

        vm.expectRevert(abi.encodeWithSelector(INodeManager.InvalidNodeDefinition.selector, nodeDefinition));
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_Revert_InvalidAggregatorV3Definition() public {
        NodeDefinition.Data memory nodeDefinition = _aggregatorV3Node(address(new MockAggregatorV3(8, 2000e8, 900)));
        nodeDefinition.parameters = abi.encodePacked(nodeDefinition.parameters, uint8(0));

        vm.expectRevert(abi.encodeWithSelector(INodeManager.InvalidNodeDefinition.selector, nodeDefinition));
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_Revert_InvalidVaultSharePriceDefinition() public {
        MockERC4626Vault vault = new MockERC4626Vault(address(new MockERC20Decimals(6)), 18, 1.05e6);
        NodeDefinition.Data memory nodeDefinition = _vaultSharePriceNode(address(vault), new bytes32[](0));

        vm.expectRevert(abi.encodeWithSelector(INodeManager.InvalidNodeDefinition.selector, nodeDefinition));
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_Revert_VaultSharePriceVaultReverts() public {
        MockERC4626Vault vault = new MockERC4626Vault(address(new MockERC20Decimals(6)), 18, 1.05e6);
        vault.setShouldRevertOnConvertToAssets(true);
        bytes32 parentId = _registerConstant(nodeManager, 1e18);
        NodeDefinition.Data memory nodeDefinition = _vaultSharePriceNode(address(vault), _parents(parentId));

        vm.expectRevert(MockERC4626Vault.ConvertToAssetsReverted.selector);
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_Revert_AggregatorV3HasNoCode() public {
        NodeDefinition.Data memory nodeDefinition = _aggregatorV3Node(makeAddr("eoa"));

        vm.expectRevert();
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_StoresSequencerUptimeNodeWhileSequencerIsDown() public {
        MockAggregatorV3 feed = new MockAggregatorV3(0, 1, 900);
        bytes32 parentId = _registerConstant(nodeManager, 1e18);
        NodeDefinition.Data memory nodeDefinition = _sequencerUptimeNode(address(feed), 3600, _parents(parentId));

        bytes32 nodeId =
            nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        NodeDefinition.Data memory stored = nodeManager.getNode(nodeId);
        assertEq(uint8(stored.nodeType), uint8(NodeDefinition.NodeType.SEQUENCER_UPTIME));
        assertEq(stored.parameters, nodeDefinition.parameters);
        assertEq(stored.parents.length, 1);
        assertEq(stored.parents[0], parentId);
    }

    function test_RegisterNode_Revert_InvalidSequencerUptimeDefinition() public {
        NodeDefinition.Data memory nodeDefinition =
            _sequencerUptimeNode(address(new MockAggregatorV3(0, 0, 900)), 3600, new bytes32[](0));

        vm.expectRevert(abi.encodeWithSelector(INodeManager.InvalidNodeDefinition.selector, nodeDefinition));
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_Revert_SequencerUptimeParentNotRegistered() public {
        bytes32 unregisteredParentId = bytes32(uint256(0xdead));
        NodeDefinition.Data memory nodeDefinition =
            _sequencerUptimeNode(address(new MockAggregatorV3(0, 0, 900)), 3600, _parents(unregisteredParentId));

        vm.expectRevert(abi.encodeWithSelector(INodeManager.NodeNotRegistered.selector, unregisteredParentId));
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_StoresExternalNodeWithoutParents() public {
        NodeDefinition.Data memory nodeDefinition =
            _externalNode(address(new MockExternalNode(1e18, 900)), new bytes32[](0));

        bytes32 nodeId =
            nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        NodeDefinition.Data memory stored = nodeManager.getNode(nodeId);
        assertEq(uint8(stored.nodeType), uint8(NodeDefinition.NodeType.EXTERNAL));
        assertEq(stored.parameters, nodeDefinition.parameters);
        assertEq(stored.parents.length, 0);
    }

    function test_RegisterNode_StoresExternalNodeWithParents() public {
        bytes32 firstId = _registerConstant(nodeManager, 3e18);
        bytes32 secondId = _registerConstant(nodeManager, 2e18);
        NodeDefinition.Data memory nodeDefinition =
            _externalNode(address(new MockProductExternalNode()), _parents(firstId, secondId));

        bytes32 nodeId =
            nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        NodeDefinition.Data memory stored = nodeManager.getNode(nodeId);
        assertEq(uint8(stored.nodeType), uint8(NodeDefinition.NodeType.EXTERNAL));
        assertEq(stored.parents.length, 2);
        assertEq(stored.parents[0], firstId);
        assertEq(stored.parents[1], secondId);
    }

    function test_RegisterNode_ExternalNodeReentersWhenValidatedWithoutStaticcall() public {
        MockReentrantExternalNode reentrantNode = new MockReentrantExternalNode(INodeManager(address(nodeManager)));
        NodeDefinition.Data memory nodeDefinition = _externalNode(address(reentrantNode), new bytes32[](0));
        bytes32 nodeId =
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        reentrantNode.isValid(nodeDefinition);

        assertTrue(nodeManager.isNodeRegistered(nodeId));
    }

    function test_RegisterNode_Revert_InvalidExternalDefinition() public {
        MockExternalNode externalNode = new MockExternalNode(1e18, 900);
        externalNode.setIsValid(false);
        NodeDefinition.Data memory nodeDefinition = _externalNode(address(externalNode), new bytes32[](0));

        vm.expectRevert(abi.encodeWithSelector(INodeManager.InvalidNodeDefinition.selector, nodeDefinition));
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_Revert_ExternalNodeReentersRegisterNode() public {
        MockReentrantExternalNode reentrantNode = new MockReentrantExternalNode(INodeManager(address(nodeManager)));
        NodeDefinition.Data memory nodeDefinition = _externalNode(address(reentrantNode), new bytes32[](0));

        vm.expectRevert();
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    function test_RegisterNode_Revert_ExternalParentNotRegistered() public {
        bytes32 registeredParentId = _registerConstant(nodeManager, 1e18);
        bytes32 unregisteredParentId = bytes32(uint256(0xdead));
        NodeDefinition.Data memory nodeDefinition =
            _externalNode(address(new MockProductExternalNode()), _parents(registeredParentId, unregisteredParentId));

        vm.expectRevert(abi.encodeWithSelector(INodeManager.NodeNotRegistered.selector, unregisteredParentId));
        nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);
    }

    // isNodeRegistered()

    function test_IsNodeRegistered_TrueAfterRegistration() public {
        NodeDefinition.Data memory nodeDefinition = _constantNode(1e18);

        bytes32 nodeId =
            nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        assertTrue(nodeManager.isNodeRegistered(nodeId));
    }

    function test_IsNodeRegistered_FalseBeforeRegistration() public view {
        NodeDefinition.Data memory nodeDefinition = _constantNode(1e18);
        bytes32 nodeId =
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        assertFalse(nodeManager.isNodeRegistered(nodeId));
    }

    // process()

    function test_Process_ConstantReturnsCorrectOutput() public {
        uint256 price = 1e18;
        bytes32 nodeId = _registerConstant(nodeManager, price);
        vm.warp(99_999);

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, price);
        assertEq(output.timestamp, 99_999);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
        assertEq(output.additionalParam1, 0);
        assertEq(output.additionalParam2, 0);
    }

    function test_Process_StalenessReturnsFreshPrimaryParent() public {
        vm.warp(99_999);
        bytes32 primaryId = _registerConstant(nodeManager, 1e18);
        bytes32 fallbackId = _registerConstant(nodeManager, 2e18);
        bytes32 nodeId = _registerStaleness(nodeManager, 100, _parents(primaryId, fallbackId));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 1e18);
        assertEq(output.timestamp, 99_999);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
    }

    function test_Process_StalenessReturnsFallbackWhenPrimaryIsStale() public {
        vm.warp(99_999);
        bytes32 primaryId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 2000e8, 99_899)));
        bytes32 fallbackId = _registerConstant(nodeManager, 2e18);
        bytes32 nodeId = _registerStaleness(nodeManager, 99, _parents(primaryId, fallbackId));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 2e18);
        assertEq(output.timestamp, 99_999);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
    }

    function test_Process_Revert_StalenessPrimaryIsStaleWithoutFallback() public {
        vm.warp(99_999);
        bytes32 primaryId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 2000e8, 99_899)));
        bytes32 nodeId = _registerStaleness(nodeManager, 99, _parents(primaryId));

        vm.expectRevert(
            abi.encodeWithSelector(
                StalenessCircuitBreakerNode.StalenessToleranceExceeded.selector,
                NodeDefinition.NodeType.AGGREGATOR_V3,
                99_899
            )
        );
        nodeManager.process(nodeId);
    }

    function test_Process_ReducerRecentReturnsLatestParent() public {
        bytes32 middleId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 1e8, 200)));
        bytes32 latestId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 2e8, 300)));
        bytes32 oldestId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 3e8, 100)));
        bytes32 nodeId =
            _registerReducer(nodeManager, ReducerNode.Operation.RECENT, _parents(middleId, latestId, oldestId));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 2e18);
        assertEq(output.timestamp, 300);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.AGGREGATOR_V3));
    }

    function test_Process_ReducerMedianReturnsMiddleParent() public {
        bytes32 firstId = _registerConstant(nodeManager, 3e18);
        bytes32 secondId = _registerConstant(nodeManager, 1e18);
        bytes32 thirdId = _registerConstant(nodeManager, 2e18);
        bytes32 nodeId =
            _registerReducer(nodeManager, ReducerNode.Operation.MEDIAN, _parents(firstId, secondId, thirdId));
        vm.warp(99_999);

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 2e18);
        assertEq(output.timestamp, 99_999);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
    }

    function test_Process_ReducerMeanReturnsComputedOutput() public {
        bytes32 firstId = _registerConstant(nodeManager, 1e18);
        bytes32 secondId = _registerConstant(nodeManager, 3e18);
        bytes32 nodeId = _registerReducer(nodeManager, ReducerNode.Operation.MEAN, _parents(firstId, secondId));
        vm.warp(99_999);

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 2e18);
        assertEq(output.timestamp, 99_999);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.REDUCER));
    }

    function test_Process_Revert_ReducerDivDecimalByZero() public {
        bytes32 firstId = _registerConstant(nodeManager, 1e18);
        bytes32 secondId = _registerConstant(nodeManager, 0);
        bytes32 nodeId = _registerReducer(nodeManager, ReducerNode.Operation.DIV_DECIMAL, _parents(firstId, secondId));

        vm.expectRevert(abi.encodeWithSelector(ReducerNode.DivisionByZero.selector, 1));
        nodeManager.process(nodeId);
    }

    function test_Process_PriceDeviationReturnsPrimaryWithinTolerance() public {
        bytes32 primaryId = _registerConstant(nodeManager, 100e18);
        bytes32 comparisonId = _registerConstant(nodeManager, 101e18);
        bytes32 nodeId = _registerPriceDeviation(nodeManager, 0.01e18, _parents(primaryId, comparisonId));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 100e18);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
    }

    function test_Process_PriceDeviationReturnsFallbackBeyondTolerance() public {
        bytes32 primaryId = _registerConstant(nodeManager, 100e18);
        bytes32 comparisonId = _registerConstant(nodeManager, 102e18);
        bytes32 fallbackId = _registerConstant(nodeManager, 7e18);
        bytes32 nodeId = _registerPriceDeviation(nodeManager, 0.01e18, _parents(primaryId, comparisonId, fallbackId));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 7e18);
    }

    function test_Process_Revert_PriceDeviationExceeded() public {
        bytes32 primaryId = _registerConstant(nodeManager, 100e18);
        bytes32 comparisonId = _registerConstant(nodeManager, 102e18);
        bytes32 nodeId = _registerPriceDeviation(nodeManager, 0.01e18, _parents(primaryId, comparisonId));

        vm.expectRevert(
            abi.encodeWithSelector(PriceDeviationCircuitBreakerNode.DeviationToleranceExceeded.selector, 0.02e18)
        );
        nodeManager.process(nodeId);
    }

    function test_Process_Revert_PriceDeviationZeroPrice() public {
        bytes32 primaryId = _registerConstant(nodeManager, 0);
        bytes32 comparisonId = _registerConstant(nodeManager, 1e18);
        bytes32 nodeId = _registerPriceDeviation(nodeManager, 0.01e18, _parents(primaryId, comparisonId));

        vm.expectRevert(
            abi.encodeWithSelector(
                PriceDeviationCircuitBreakerNode.ZeroPrice.selector, NodeDefinition.NodeType.CONSTANT
            )
        );
        nodeManager.process(nodeId);
    }

    function test_Process_AggregatorV3ReturnsScaledAnswer() public {
        bytes32 nodeId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 2000e8, 900)));
        vm.warp(99_999);

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 2000e18);
        assertEq(output.timestamp, 900);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.AGGREGATOR_V3));
        assertEq(output.additionalParam1, 0);
        assertEq(output.additionalParam2, 0);
    }

    function test_Process_Revert_AggregatorV3NegativeAnswer() public {
        MockAggregatorV3 aggregator = new MockAggregatorV3(8, 2000e8, 900);
        bytes32 nodeId = _registerAggregatorV3(nodeManager, address(aggregator));
        aggregator.setAnswer(-1, 900);

        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedIntToUint.selector, -1));
        nodeManager.process(nodeId);
    }

    function test_Process_VaultSharePriceReturnsSharePrice() public {
        bytes32 parentId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 2000e8, 900)));
        MockERC4626Vault vault = new MockERC4626Vault(address(new MockERC20Decimals(6)), 18, 1.05e6);
        bytes32 nodeId = _registerVaultSharePrice(nodeManager, address(vault), _parents(parentId));
        vm.warp(99_999);

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 2100e18);
        assertEq(output.timestamp, 900);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.VAULT_SHARE_PRICE));
        assertEq(output.additionalParam1, 0);
        assertEq(output.additionalParam2, 0);
    }

    function test_Process_VaultSharePriceReturnsZeroForZeroRate() public {
        bytes32 parentId = _registerConstant(nodeManager, 1e18);
        MockERC4626Vault vault = new MockERC4626Vault(address(new MockERC20Decimals(6)), 18, 1.05e6);
        bytes32 nodeId = _registerVaultSharePrice(nodeManager, address(vault), _parents(parentId));
        vault.setRate(0);

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 0);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.VAULT_SHARE_PRICE));
    }

    function test_Process_SequencerUptimeReturnsParentOutputWhenSequencerIsUp() public {
        bytes32 parentId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 2000e8, 900)));
        MockAggregatorV3 feed = new MockAggregatorV3(0, 0, 800);
        bytes32 nodeId = _registerSequencerUptime(nodeManager, address(feed), 3600, _parents(parentId));
        vm.warp(99_999);

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 2000e18);
        assertEq(output.timestamp, 900);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.AGGREGATOR_V3));
        assertEq(output.additionalParam1, 0);
        assertEq(output.additionalParam2, 0);
    }

    function test_Process_Revert_SequencerUptimeSequencerDown() public {
        bytes32 parentId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 2000e8, 900)));
        MockAggregatorV3 feed = new MockAggregatorV3(0, 0, 800);
        bytes32 nodeId = _registerSequencerUptime(nodeManager, address(feed), 3600, _parents(parentId));
        feed.setRoundData(2, 1, 950, 950, 2);

        vm.expectRevert(abi.encodeWithSelector(SequencerUptimeNode.SequencerDown.selector, address(feed)));
        nodeManager.process(nodeId);
    }

    function test_Process_Revert_SequencerUptimeGracePeriodNotOver() public {
        bytes32 parentId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 2000e8, 900)));
        MockAggregatorV3 feed = new MockAggregatorV3(0, 0, 99_000);
        bytes32 nodeId = _registerSequencerUptime(nodeManager, address(feed), 3600, _parents(parentId));
        vm.warp(99_999);

        vm.expectRevert(abi.encodeWithSelector(SequencerUptimeNode.GracePeriodNotOver.selector, address(feed)));
        nodeManager.process(nodeId);
    }

    function test_Process_Revert_SequencerUptimeReportsParentErrorWhenParentRevertsFirst() public {
        vm.warp(99_999);
        bytes32 aggregatorId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 2000e8, 99_899)));
        bytes32 stalenessId = _registerStaleness(nodeManager, 99, _parents(aggregatorId));
        MockAggregatorV3 feed = new MockAggregatorV3(0, 1, 99_000);
        bytes32 nodeId = _registerSequencerUptime(nodeManager, address(feed), 3600, _parents(stalenessId));

        vm.expectRevert(
            abi.encodeWithSelector(
                StalenessCircuitBreakerNode.StalenessToleranceExceeded.selector,
                NodeDefinition.NodeType.AGGREGATOR_V3,
                99_899
            )
        );
        nodeManager.process(nodeId);
    }

    function test_Process_ExternalReturnsOutputTypedExternal() public {
        MockExternalNode externalNode = new MockExternalNode(1e18, 900);
        externalNode.setOutput(NodeOutput.Data(2000e18, 900, NodeDefinition.NodeType.CONSTANT, 7, 8));
        bytes32 nodeId = _registerExternal(nodeManager, address(externalNode), new bytes32[](0));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 2000e18);
        assertEq(output.timestamp, 900);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.EXTERNAL));
        assertEq(output.additionalParam1, 7);
        assertEq(output.additionalParam2, 8);
    }

    function test_Process_ExternalReturnsProductOfParents() public {
        bytes32 firstId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 3e8, 300)));
        bytes32 secondId = _registerAggregatorV3(nodeManager, address(new MockAggregatorV3(8, 2e8, 200)));
        bytes32 nodeId =
            _registerExternal(nodeManager, address(new MockProductExternalNode()), _parents(firstId, secondId));

        NodeOutput.Data memory output = nodeManager.process(nodeId);

        assertEq(output.price, 6e18);
        assertEq(output.timestamp, 200);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.EXTERNAL));
    }

    function test_Process_Revert_ExternalNodeReverts() public {
        MockExternalNode externalNode = new MockExternalNode(1e18, 900);
        bytes32 nodeId = _registerExternal(nodeManager, address(externalNode), new bytes32[](0));
        externalNode.setShouldRevertOnProcess(true);

        vm.expectRevert(MockExternalNode.ProcessReverted.selector);
        nodeManager.process(nodeId);
    }

    function test_Process_Revert_StalenessReportsExternalTypeForStaleExternalPrimary() public {
        vm.warp(99_999);
        MockExternalNode externalNode = new MockExternalNode(1e18, 99_899);
        externalNode.setOutput(NodeOutput.Data(1e18, 99_899, NodeDefinition.NodeType.CONSTANT, 0, 0));
        bytes32 primaryId = _registerExternal(nodeManager, address(externalNode), new bytes32[](0));
        bytes32 nodeId = _registerStaleness(nodeManager, 99, _parents(primaryId));

        vm.expectRevert(
            abi.encodeWithSelector(
                StalenessCircuitBreakerNode.StalenessToleranceExceeded.selector,
                NodeDefinition.NodeType.EXTERNAL,
                99_899
            )
        );
        nodeManager.process(nodeId);
    }

    function test_Process_Revert_NotRegistered() public {
        bytes32 nodeId = bytes32(uint256(0xdead));

        vm.expectRevert(abi.encodeWithSelector(INodeManager.NodeNotRegistered.selector, nodeId));
        nodeManager.process(nodeId);
    }

    // @dev UnprocessableNode is unreachable while every NodeDefinition.NodeType other than NONE has a processor —
    // NONE is already rejected at registration, so no registered node can reach that revert branch.

    // getNodeId()

    function test_GetNodeId_ReturnsDeterministicHash() public view {
        NodeDefinition.Data memory nodeDefinition = _constantNode(1e18);

        assertEq(
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents),
            nodeManager.getNodeId(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents)
        );
    }

    function test_GetNodeId_DifferentParamsDifferentId() public view {
        NodeDefinition.Data memory a = _constantNode(1e18);
        NodeDefinition.Data memory b = _constantNode(2e18);

        assertNotEq(
            nodeManager.getNodeId(a.nodeType, a.parameters, a.parents),
            nodeManager.getNodeId(b.nodeType, b.parameters, b.parents)
        );
    }

    // getNode()

    function test_GetNode_ReturnsStoredData() public {
        NodeDefinition.Data memory nodeDefinition = _constantNode(1e18);
        bytes32 nodeId =
            nodeManager.registerNode(nodeDefinition.nodeType, nodeDefinition.parameters, nodeDefinition.parents);

        NodeDefinition.Data memory stored = nodeManager.getNode(nodeId);

        assertEq(uint8(stored.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
        assertEq(stored.parameters, nodeDefinition.parameters);
        assertEq(stored.parents.length, 0);
    }

    function test_GetNode_ReturnsZeroValueDataForUnregistered() public view {
        bytes32 nodeId = bytes32(uint256(0xdead));

        NodeDefinition.Data memory stored = nodeManager.getNode(nodeId);

        assertEq(uint8(stored.nodeType), uint8(NodeDefinition.NodeType.NONE));
        assertEq(stored.parameters.length, 0);
        assertEq(stored.parents.length, 0);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(nodeManager.contractName(), "NodeManager");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(nodeManager.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_SupportsInterface_INodeManager() public view {
        assertTrue(nodeManager.supportsInterface(type(INodeManager).interfaceId));
    }

    function test_SupportsInterface_IERC165() public view {
        assertTrue(nodeManager.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsInterface_IVersioned() public view {
        assertTrue(nodeManager.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_SupportsInterface_ReturnsFalseForUnknown() public view {
        assertFalse(nodeManager.supportsInterface(bytes4(0xdeadbeef)));
    }

    function _deployNodeManager(NodeDefinition.Data[] memory nodes) internal returns (NodeManager instance) {
        instance = _clone();
        instance.initialize(nodes);
    }

    function _clone() internal returns (NodeManager) {
        return NodeManager(Clones.clone(address(implementation)));
    }
}
