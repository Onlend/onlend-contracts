// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ExternalNode} from "src/oracle/node-manager/lib/nodes/ExternalNode.sol";
import {IExternalNode} from "src/oracle/node-manager/interfaces/IExternalNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {MockExternalNode} from "../../mocks/MockExternalNode.sol";

contract ExternalNodeFuzzTest is Test {
    MockExternalNode internal externalNode;

    function setUp() public {
        externalNode = new MockExternalNode(2000e18, 1);
    }

    // process()

    function testFuzz_Process_ReturnsExternalOutputTypedExternal(
        uint256 price,
        uint256 timestamp,
        uint8 nodeType,
        uint256 additionalParam1,
        uint256 additionalParam2
    ) public {
        nodeType = uint8(bound(nodeType, 0, uint8(type(NodeDefinition.NodeType).max)));
        externalNode.setOutput(
            NodeOutput.Data(price, timestamp, NodeDefinition.NodeType(nodeType), additionalParam1, additionalParam2)
        );

        NodeOutput.Data memory output = ExternalNode.process(new NodeOutput.Data[](0), _params(address(externalNode)));

        assertEq(output.price, price);
        assertEq(output.timestamp, timestamp);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.EXTERNAL));
        assertEq(output.additionalParam1, additionalParam1);
        assertEq(output.additionalParam2, additionalParam2);
    }

    function testFuzz_Process_ForwardsParametersUnchanged(bytes memory custom) public {
        bytes memory parameters = _params(address(externalNode), custom);

        vm.expectCall(
            address(externalNode), abi.encodeCall(IExternalNode.process, (new NodeOutput.Data[](0), parameters)), 1
        );
        ExternalNode.process(new NodeOutput.Data[](0), parameters);
    }

    function testFuzz_Process_ForwardsParentOutputsUnchanged(
        uint256 firstPrice,
        uint256 firstTimestamp,
        uint256 secondPrice,
        uint256 secondTimestamp
    ) public {
        NodeOutput.Data[] memory parentNodeOutputs = new NodeOutput.Data[](2);
        parentNodeOutputs[0] = NodeOutput.Data(firstPrice, firstTimestamp, NodeDefinition.NodeType.CONSTANT, 0, 0);
        parentNodeOutputs[1] = NodeOutput.Data(secondPrice, secondTimestamp, NodeDefinition.NodeType.CONSTANT, 0, 0);
        bytes memory parameters = _params(address(externalNode));

        vm.expectCall(address(externalNode), abi.encodeCall(IExternalNode.process, (parentNodeOutputs, parameters)), 1);
        ExternalNode.process(parentNodeOutputs, parameters);
    }

    // isValid()

    function testFuzz_IsValid_ReturnsTrueWhenParamsAtLeast32Bytes(bytes memory custom, uint256 parentCount)
        public
        view
    {
        parentCount = bound(parentCount, 0, 16);

        assertTrue(ExternalNode.isValid(_definition(_params(address(externalNode), custom), parentCount)));
    }

    function testFuzz_IsValid_ForwardsNodeDefinitionUnchanged(bytes memory custom, uint256 parentCount) public {
        parentCount = bound(parentCount, 0, 16);
        NodeDefinition.Data memory nodeDefinition = _definition(_params(address(externalNode), custom), parentCount);

        vm.expectCall(address(externalNode), abi.encodeCall(IExternalNode.isValid, (nodeDefinition)), 1);
        ExternalNode.isValid(nodeDefinition);
    }

    function testFuzz_IsValid_ReturnsFalseWhenParamsBelow32Bytes(uint256 length) public view {
        length = bound(length, 0, 31);

        assertFalse(ExternalNode.isValid(_definition(new bytes(length), 0)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenExternalNodeHasNoCode(uint256 privateKey, bytes memory custom)
        public
        view
    {
        privateKey = bound(privateKey, 1, SECP256K1_ORDER - 1);

        assertFalse(ExternalNode.isValid(_definition(_params(vm.addr(privateKey), custom), 0)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenExternalIsValidReturnsFalse(bytes memory custom, uint256 parentCount)
        public
    {
        parentCount = bound(parentCount, 0, 16);
        externalNode.setIsValid(false);

        assertFalse(ExternalNode.isValid(_definition(_params(address(externalNode), custom), parentCount)));
    }

    function testFuzz_IsValid_RevertsWhenAddressAboveMax(uint256 raw, bytes memory custom) public {
        raw = bound(raw, uint256(type(uint160).max) + 1, type(uint256).max);

        vm.expectRevert();
        this.isValid(_definition(abi.encodePacked(raw, custom), 0));
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function isValid(NodeDefinition.Data memory nodeDefinition) external view returns (bool) {
        return ExternalNode.isValid(nodeDefinition);
    }

    function _params(address target) internal pure returns (bytes memory) {
        return abi.encode(target);
    }

    function _params(address target, bytes memory custom) internal pure returns (bytes memory) {
        return abi.encodePacked(abi.encode(target), custom);
    }

    function _definition(bytes memory parameters, uint256 parentCount)
        internal
        pure
        returns (NodeDefinition.Data memory)
    {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.EXTERNAL, parameters: parameters, parents: new bytes32[](parentCount)
        });
    }
}
