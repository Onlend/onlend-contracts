// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {NodeOracle} from "src/oracle/NodeOracle.sol";
import {IOracle} from "src/oracle/interfaces/IOracle.sol";
import {INodeOracle} from "src/oracle/interfaces/INodeOracle.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockNodeManager} from "./mocks/MockNodeManager.sol";
import {MockPool} from "../pool/mocks/MockPool.sol";

contract NodeOracleUnitTest is Test {
    address internal defaultAdmin;
    address internal nodeUpdater;
    address internal nonNodeUpdater;
    IPool internal pool;
    MockNodeManager internal nodeManager;
    NodeOracle internal implementation;
    NodeOracle internal nodeOracle;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        nodeUpdater = makeAddr("nodeUpdater");
        nonNodeUpdater = makeAddr("nonNodeUpdater");
        pool = new MockPool();
        nodeManager = new MockNodeManager();
        implementation = new NodeOracle();

        nodeOracle =
            _deployNodeOracle(defaultAdmin, nodeUpdater, address(nodeManager), new NodeOracle.PoolNodeConfig[](0));
    }

    // initialize()

    function test_initialize_GrantsDefaultAdminRole() public view {
        assertTrue(nodeOracle.hasRole(nodeOracle.DEFAULT_ADMIN_ROLE(), defaultAdmin));
    }

    function test_initialize_GrantsNodeUpdaterRole() public view {
        assertTrue(nodeOracle.hasRole(nodeOracle.NODE_UPDATER_ROLE(), nodeUpdater));
    }

    function test_initialize_AllowsZeroAddressRoleMembers() public {
        NodeOracle rolelessNodeOracle =
            _deployNodeOracle(address(0), address(0), address(nodeManager), new NodeOracle.PoolNodeConfig[](0));

        assertEq(rolelessNodeOracle.getRoleMemberCount(rolelessNodeOracle.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(rolelessNodeOracle.getRoleMemberCount(rolelessNodeOracle.NODE_UPDATER_ROLE()), 0);
    }

    function test_initialize_SetsNodeManager() public view {
        assertEq(address(nodeOracle.getNodeManager()), address(nodeManager));
    }

    function test_initialize_EmitsNodeManagerSet() public {
        vm.expectEmit();
        emit INodeOracle.NodeManagerSet(address(nodeManager));

        _deployNodeOracle(defaultAdmin, nodeUpdater, address(nodeManager), new NodeOracle.PoolNodeConfig[](0));
    }

    function test_initialize_SetsMultiplePoolNodes() public {
        IPool secondPool = new MockPool();
        bytes32 firstNodeId = keccak256("first");
        bytes32 secondNodeId = keccak256("second");
        NodeOracle.PoolNodeConfig[] memory poolNodes = new NodeOracle.PoolNodeConfig[](2);
        poolNodes[0] = NodeOracle.PoolNodeConfig({pool: address(pool), nodeId: firstNodeId, assetDecimals: 6});
        poolNodes[1] = NodeOracle.PoolNodeConfig({pool: address(secondPool), nodeId: secondNodeId, assetDecimals: 18});

        NodeOracle instance = _deployNodeOracle(defaultAdmin, nodeUpdater, address(nodeManager), poolNodes);

        INodeOracle.OracleNode memory firstNode = instance.getPoolNode(pool);
        INodeOracle.OracleNode memory secondNode = instance.getPoolNode(secondPool);
        assertEq(firstNode.nodeId, firstNodeId);
        assertEq(firstNode.assetDecimals, 6);
        assertEq(secondNode.nodeId, secondNodeId);
        assertEq(secondNode.assetDecimals, 18);
    }

    function test_initialize_Revert_InvalidNodeManager() public {
        nodeManager.setSupportsInterfaceOverride(false);
        NodeOracle instance = _clone();

        vm.expectRevert(abi.encodeWithSelector(INodeOracle.InvalidNodeManager.selector, address(nodeManager)));
        instance.initialize(defaultAdmin, nodeUpdater, address(nodeManager), new NodeOracle.PoolNodeConfig[](0));
    }

    // setNodeManager()

    function test_setNodeManager_SetsNodeManager() public {
        MockNodeManager newNodeManager = new MockNodeManager();

        vm.prank(nodeUpdater);
        nodeOracle.setNodeManager(address(newNodeManager));

        assertEq(address(nodeOracle.getNodeManager()), address(newNodeManager));
    }

    function test_setNodeManager_EmitsNodeManagerSet() public {
        MockNodeManager newNodeManager = new MockNodeManager();

        vm.expectEmit();
        emit INodeOracle.NodeManagerSet(address(newNodeManager));

        vm.prank(nodeUpdater);
        nodeOracle.setNodeManager(address(newNodeManager));
    }

    function test_setNodeManager_Revert_NotNodeUpdater() public {
        MockNodeManager newNodeManager = new MockNodeManager();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonNodeUpdater, nodeOracle.NODE_UPDATER_ROLE()
            )
        );
        vm.prank(nonNodeUpdater);
        nodeOracle.setNodeManager(address(newNodeManager));
    }

    function test_setNodeManager_Revert_InvalidNodeManager() public {
        MockNodeManager newNodeManager = new MockNodeManager();
        newNodeManager.setSupportsInterfaceOverride(false);

        vm.expectRevert(abi.encodeWithSelector(INodeOracle.InvalidNodeManager.selector, address(newNodeManager)));
        vm.prank(nodeUpdater);
        nodeOracle.setNodeManager(address(newNodeManager));
    }

    // setNodeId()

    function test_setNodeId_SetsPoolNode() public {
        bytes32 nodeId = keccak256("node");

        vm.prank(nodeUpdater);
        nodeOracle.setNodeId(address(pool), nodeId, 6);

        INodeOracle.OracleNode memory node = nodeOracle.getPoolNode(pool);
        assertEq(node.nodeId, nodeId);
        assertEq(node.assetDecimals, 6);
    }

    function test_setNodeId_EmitsNodeIdSetForPool() public {
        bytes32 nodeId = keccak256("node");

        vm.expectEmit();
        emit INodeOracle.NodeIdSetForPool(pool, nodeId, 6);

        vm.prank(nodeUpdater);
        nodeOracle.setNodeId(address(pool), nodeId, 6);
    }

    function test_setNodeId_OverwritesExistingPoolNode() public {
        vm.prank(nodeUpdater);
        nodeOracle.setNodeId(address(pool), keccak256("first"), 6);

        bytes32 newNodeId = keccak256("second");
        vm.prank(nodeUpdater);
        nodeOracle.setNodeId(address(pool), newNodeId, 18);

        INodeOracle.OracleNode memory node = nodeOracle.getPoolNode(pool);
        assertEq(node.nodeId, newNodeId);
        assertEq(node.assetDecimals, 18);
    }

    function test_setNodeId_Revert_NotNodeUpdater() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonNodeUpdater, nodeOracle.NODE_UPDATER_ROLE()
            )
        );
        vm.prank(nonNodeUpdater);
        nodeOracle.setNodeId(address(pool), keccak256("node"), 6);
    }

    function test_setNodeId_Revert_NodeProcessingReverts() public {
        nodeManager.setShouldRevertOnProcess(true);

        vm.expectRevert(MockNodeManager.ProcessReverted.selector);
        vm.prank(nodeUpdater);
        nodeOracle.setNodeId(address(pool), keccak256("node"), 6);
    }

    // getPrice()

    function test_getPrice_ReturnsPriceAndAssetDecimals() public {
        bytes32 nodeId = keccak256("node");
        uint256 price = 2000e18;
        uint8 assetDecimals = 6;
        vm.prank(nodeUpdater);
        nodeOracle.setNodeId(address(pool), nodeId, assetDecimals);
        NodeOutput.Data memory output;
        output.price = price;
        nodeManager.setOutput(output);

        IOracle.PriceFeed memory priceFeed = nodeOracle.getPrice(pool);

        assertEq(priceFeed.price, price);
        assertEq(priceFeed.assetDecimals, assetDecimals);
    }

    function test_getPrice_Revert_NoNodeIdForPool() public {
        vm.expectRevert(abi.encodeWithSelector(INodeOracle.NoNodeIdForPool.selector, pool));
        nodeOracle.getPrice(pool);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(nodeOracle.contractName(), "NodeOracle");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(nodeOracle.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_SupportsIAccessControl() public view {
        assertTrue(nodeOracle.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_SupportsIAccessControlEnumerable() public view {
        assertTrue(nodeOracle.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_SupportsIOracle() public view {
        assertTrue(nodeOracle.supportsInterface(type(IOracle).interfaceId));
    }

    function test_supportsInterface_SupportsINodeOracle() public view {
        assertTrue(nodeOracle.supportsInterface(type(INodeOracle).interfaceId));
    }

    function test_supportsInterface_SupportsIVersioned() public view {
        assertTrue(nodeOracle.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_SupportsIERC165() public view {
        assertTrue(nodeOracle.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_ReturnsFalseForUnsupportedInterface() public view {
        assertFalse(nodeOracle.supportsInterface(bytes4(0xffffffff)));
    }

    function _deployNodeOracle(
        address defaultAdmin_,
        address nodeUpdater_,
        address nodeManager_,
        NodeOracle.PoolNodeConfig[] memory poolNodes
    ) internal returns (NodeOracle instance) {
        instance = _clone();
        instance.initialize(defaultAdmin_, nodeUpdater_, nodeManager_, poolNodes);
    }

    function _clone() internal returns (NodeOracle) {
        return NodeOracle(Clones.clone(address(implementation)));
    }
}
