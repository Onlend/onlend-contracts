// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {NodeManagerFactory} from "src/factories/oracle/node-manager/NodeManagerFactory.sol";
import {NodeManager} from "src/oracle/node-manager/NodeManager.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";

contract NodeManagerFactoryUnitTest is Test {
    NodeManagerFactory factory;
    NodeManager implementation;

    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        implementation = new NodeManager();
        factory = new NodeManagerFactory(address(implementation));
    }

    // clone()

    function test_Clone_InitializesCloneWithDecodedNodes() public {
        NodeDefinition.Data[] memory nodes = _nodes();

        address instance = factory.clone(SALT, abi.encode(nodes));

        NodeManager nodeManager = NodeManager(instance);
        bytes32 firstNodeId = nodeManager.getNodeId(nodes[0].nodeType, nodes[0].parameters, nodes[0].parents);
        bytes32 secondNodeId = nodeManager.getNodeId(nodes[1].nodeType, nodes[1].parameters, nodes[1].parents);
        assertTrue(nodeManager.isNodeRegistered(firstNodeId));
        assertTrue(nodeManager.isNodeRegistered(secondNodeId));
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, abi.encode(_nodes()));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "NodeManager1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    // Helpers

    function _nodes() internal pure returns (NodeDefinition.Data[] memory nodes) {
        nodes = new NodeDefinition.Data[](2);
        nodes[0] = NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.CONSTANT, parameters: abi.encode(uint256(1e18)), parents: new bytes32[](0)
        });
        nodes[1] = NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.CONSTANT, parameters: abi.encode(uint256(2e18)), parents: new bytes32[](0)
        });
    }
}
