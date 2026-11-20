// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {NodeOracle} from "src/oracle/NodeOracle.sol";
import {IOracle} from "src/oracle/interfaces/IOracle.sol";
import {INodeOracle} from "src/oracle/interfaces/INodeOracle.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockNodeManager} from "./mocks/MockNodeManager.sol";
import {MockPool} from "../pool/mocks/MockPool.sol";

contract NodeOracleFuzzTest is Test {
    address internal defaultAdmin;
    address internal nodeUpdater;
    IPool internal pool;
    MockNodeManager internal nodeManager;
    NodeOracle internal implementation;
    NodeOracle internal nodeOracle;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        nodeUpdater = makeAddr("nodeUpdater");
        pool = new MockPool();
        nodeManager = new MockNodeManager();
        implementation = new NodeOracle();

        nodeOracle = _deployNodeOracle(new NodeOracle.PoolNodeConfig[](0));
    }

    // setNodeId()

    function testFuzz_SetNodeId_StoresNodeIdAndAssetDecimals(address poolAddress, bytes32 nodeId, uint8 assetDecimals)
        public
    {
        vm.prank(nodeUpdater);
        nodeOracle.setNodeId(poolAddress, nodeId, assetDecimals);

        INodeOracle.OracleNode memory node = nodeOracle.getPoolNode(IPool(poolAddress));
        assertEq(node.nodeId, nodeId);
        assertEq(node.assetDecimals, assetDecimals);
    }

    // getPrice()

    function testFuzz_GetPrice_ReturnsNodePriceAndStoredAssetDecimals(
        bytes32 nodeId,
        uint8 assetDecimals,
        uint256 price
    ) public {
        vm.assume(nodeId != bytes32(0));
        vm.prank(nodeUpdater);
        nodeOracle.setNodeId(address(pool), nodeId, assetDecimals);
        NodeOutput.Data memory output;
        output.price = price;
        nodeManager.setOutput(output);

        IOracle.PriceFeed memory priceFeed = nodeOracle.getPrice(pool);

        assertEq(priceFeed.price, price);
        assertEq(priceFeed.assetDecimals, assetDecimals);
    }

    function _deployNodeOracle(NodeOracle.PoolNodeConfig[] memory poolNodes) internal returns (NodeOracle instance) {
        instance = NodeOracle(Clones.clone(address(implementation)));
        instance.initialize(defaultAdmin, nodeUpdater, address(nodeManager), poolNodes);
    }
}
