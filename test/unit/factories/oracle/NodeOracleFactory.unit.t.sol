// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {NodeOracleFactory} from "src/factories/oracle/NodeOracleFactory.sol";
import {NodeOracle} from "src/oracle/NodeOracle.sol";
import {INodeOracle} from "src/oracle/interfaces/INodeOracle.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockNodeManager} from "../../oracle/mocks/MockNodeManager.sol";
import {MockPool} from "../../pool/mocks/MockPool.sol";

contract NodeOracleFactoryUnitTest is Test {
    NodeOracleFactory factory;
    NodeOracle implementation;

    address defaultAdmin = makeAddr("defaultAdmin");
    address nodeUpdater = makeAddr("nodeUpdater");
    MockNodeManager nodeManager;
    IPool firstPool;
    IPool secondPool;

    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        nodeManager = new MockNodeManager();
        firstPool = new MockPool();
        secondPool = new MockPool();
        implementation = new NodeOracle();
        factory = new NodeOracleFactory(address(implementation));
    }

    // clone()

    function test_Clone_InitializesCloneWithDecodedRolesAndConfiguration() public {
        NodeOracle.PoolNodeConfig[] memory poolNodes = _poolNodes();

        address instance = factory.clone(SALT, abi.encode(defaultAdmin, nodeUpdater, address(nodeManager), poolNodes));

        NodeOracle nodeOracle = NodeOracle(instance);
        INodeOracle.OracleNode memory firstNode = nodeOracle.getPoolNode(firstPool);
        INodeOracle.OracleNode memory secondNode = nodeOracle.getPoolNode(secondPool);
        assertTrue(nodeOracle.hasRole(nodeOracle.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(nodeOracle.hasRole(nodeOracle.NODE_UPDATER_ROLE(), nodeUpdater));
        assertEq(address(nodeOracle.getNodeManager()), address(nodeManager));
        assertEq(firstNode.nodeId, poolNodes[0].nodeId);
        assertEq(firstNode.assetDecimals, poolNodes[0].assetDecimals);
        assertEq(secondNode.nodeId, poolNodes[1].nodeId);
        assertEq(secondNode.assetDecimals, poolNodes[1].assetDecimals);
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, abi.encode(defaultAdmin, nodeUpdater, address(nodeManager), _poolNodes()));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "NodeOracle1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    // Helpers

    function _poolNodes() internal view returns (NodeOracle.PoolNodeConfig[] memory poolNodes) {
        poolNodes = new NodeOracle.PoolNodeConfig[](2);
        poolNodes[0] =
            NodeOracle.PoolNodeConfig({pool: address(firstPool), nodeId: keccak256("first"), assetDecimals: 6});
        poolNodes[1] =
            NodeOracle.PoolNodeConfig({pool: address(secondPool), nodeId: keccak256("second"), assetDecimals: 18});
    }
}
