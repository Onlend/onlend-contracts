// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ConstantNode} from "src/oracle/node-manager/lib/nodes/ConstantNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

contract ConstantNodeTest is Test {
    // isValid()

    function test_IsValid_ReturnsTrueForValidNode() public pure {
        NodeDefinition.Data memory nodeDefinition = NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.CONSTANT, parameters: abi.encode(uint256(1e18)), parents: new bytes32[](0)
        });

        assertTrue(ConstantNode.isValid(nodeDefinition));
    }

    function test_IsValid_ReturnsFalseWhenHasParents() public pure {
        bytes32[] memory parents = new bytes32[](1);
        parents[0] = bytes32(uint256(1));
        NodeDefinition.Data memory nodeDefinition = NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.CONSTANT, parameters: abi.encode(uint256(1e18)), parents: parents
        });

        assertFalse(ConstantNode.isValid(nodeDefinition));
    }

    function test_IsValid_ReturnsFalseWhenParamsEmpty() public pure {
        NodeDefinition.Data memory nodeDefinition = NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.CONSTANT, parameters: "", parents: new bytes32[](0)
        });

        assertFalse(ConstantNode.isValid(nodeDefinition));
    }

    function test_IsValid_ReturnsFalseWhenParamsNot32Bytes() public pure {
        NodeDefinition.Data memory nodeDefinition = NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.CONSTANT,
            parameters: abi.encodePacked(uint128(1e18)),
            parents: new bytes32[](0)
        });

        assertFalse(ConstantNode.isValid(nodeDefinition));
    }

    // process()

    function test_Process_ReturnsCorrectOutput() public {
        uint256 price = 1e18;
        vm.warp(99_999);

        NodeOutput.Data memory output = ConstantNode.process(abi.encode(price));

        assertEq(output.price, price);
        assertEq(output.timestamp, 99_999);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
        assertEq(output.additionalParam1, 0);
        assertEq(output.additionalParam2, 0);
    }
}
