// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ConstantNode} from "src/oracle/node-manager/lib/nodes/ConstantNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

contract ConstantNodeFuzzTest is Test {
    // isValid()

    function testFuzz_IsValid_ReturnsTrueWhenValidParams(uint256 price) public pure {
        NodeDefinition.Data memory nodeDefinition = NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.CONSTANT, parameters: abi.encode(price), parents: new bytes32[](0)
        });

        assertTrue(ConstantNode.isValid(nodeDefinition));
    }

    function testFuzz_IsValid_FalseWhenParamsLengthNot32(bytes calldata parameters) public pure {
        vm.assume(parameters.length != 32);
        NodeDefinition.Data memory nodeDefinition = NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.CONSTANT, parameters: parameters, parents: new bytes32[](0)
        });

        assertFalse(ConstantNode.isValid(nodeDefinition));
    }

    function testFuzz_IsValid_FalseWhenHasParents(uint256 price, uint8 parentCount) public pure {
        parentCount = uint8(bound(parentCount, 1, 8));
        bytes32[] memory parents = new bytes32[](parentCount);
        NodeDefinition.Data memory nodeDefinition = NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.CONSTANT, parameters: abi.encode(price), parents: parents
        });

        assertFalse(ConstantNode.isValid(nodeDefinition));
    }

    // process()

    function testFuzz_Process_ReturnsEncodedPrice(uint256 price, uint256 ts) public {
        ts = bound(ts, 1, type(uint32).max);
        vm.warp(ts);

        NodeOutput.Data memory output = ConstantNode.process(abi.encode(price));

        assertEq(output.price, price);
        assertEq(output.timestamp, ts);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
        assertEq(output.additionalParam1, 0);
        assertEq(output.additionalParam2, 0);
    }
}
