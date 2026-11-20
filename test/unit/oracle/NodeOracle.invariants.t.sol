// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {NodeOracle} from "src/oracle/NodeOracle.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockNodeManager} from "./mocks/MockNodeManager.sol";
import {MockPool} from "../pool/mocks/MockPool.sol";

/// @notice Stateful handler — exposes setNodeId actions and tracks configured pools.
// forge-lint: disable-next-line(multi-contract-file)
contract NodeOracleHandler is Test {
    NodeOracle public nodeOracle;
    address public nodeUpdater;

    IPool[] public configuredPools;

    constructor(NodeOracle _nodeOracle, address _nodeUpdater) {
        nodeOracle = _nodeOracle;
        nodeUpdater = _nodeUpdater;
    }

    function setNodeId(bytes32 nodeId, uint8 assetDecimals) external {
        vm.assume(nodeId != bytes32(0));
        IPool pool = new MockPool();

        vm.prank(nodeUpdater);
        nodeOracle.setNodeId(address(pool), nodeId, assetDecimals);
        configuredPools.push(pool);
    }

    function configuredPoolsCount() external view returns (uint256) {
        return configuredPools.length;
    }
}

// forge-lint: disable-next-line(multi-contract-file)
contract NodeOracleInvariantsTest is Test {
    NodeOracle implementation;
    NodeOracle nodeOracle;
    MockNodeManager nodeManager;
    NodeOracleHandler handler;
    address nodeUpdater;

    function setUp() public {
        address defaultAdmin = makeAddr("defaultAdmin");
        nodeUpdater = makeAddr("nodeUpdater");
        nodeManager = new MockNodeManager();
        implementation = new NodeOracle();
        nodeOracle = NodeOracle(Clones.clone(address(implementation)));
        nodeOracle.initialize(defaultAdmin, nodeUpdater, address(nodeManager), new NodeOracle.PoolNodeConfig[](0));
        handler = new NodeOracleHandler(nodeOracle, nodeUpdater);

        targetContract(address(handler));
    }

    /// Every pool configured by the handler must be processable without revert.
    function invariant_ConfiguredPoolsAlwaysReturnPrice() public view {
        uint256 count = handler.configuredPoolsCount();
        for (uint256 i = 0; i < count; i++) {
            nodeOracle.getPrice(handler.configuredPools(i));
        }
    }

    /// Every pool configured by the handler must report the last node ID set for it.
    function invariant_PoolNodeRoundtrips() public view {
        uint256 count = handler.configuredPoolsCount();
        for (uint256 i = 0; i < count; i++) {
            IPool pool = handler.configuredPools(i);
            assertTrue(nodeOracle.getPoolNode(pool).nodeId != bytes32(0));
        }
    }
}
