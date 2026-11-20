// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {ExternalNode} from "src/oracle/node-manager/lib/nodes/ExternalNode.sol";
import {IExternalNode} from "src/oracle/node-manager/interfaces/IExternalNode.sol";
import {INodeManager} from "src/oracle/node-manager/interfaces/INodeManager.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeManager} from "src/oracle/node-manager/NodeManager.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {MockCatchAllERC165ExternalNode} from "../../mocks/MockCatchAllERC165ExternalNode.sol";
import {MockExternalNode} from "../../mocks/MockExternalNode.sol";
import {MockNoERC165ExternalNode} from "../../mocks/MockNoERC165ExternalNode.sol";
import {MockProductExternalNode} from "../../mocks/MockProductExternalNode.sol";
import {MockReentrantExternalNode} from "../../mocks/MockReentrantExternalNode.sol";

contract ExternalNodeTest is Test {
    uint256 internal constant TIMESTAMP = 900;

    /// @dev Identity precompile: echoes its input, so a naive ERC-165 query reads a non-zero word back.
    address internal constant IDENTITY_PRECOMPILE = address(4);

    MockExternalNode internal externalNode;
    MockProductExternalNode internal productNode;

    function setUp() public {
        externalNode = new MockExternalNode(2000e18, TIMESTAMP);
        productNode = new MockProductExternalNode();
    }

    // process()

    function test_Process_ReturnsExternalOutput() public {
        externalNode.setOutput(NodeOutput.Data(2000e18, TIMESTAMP, NodeDefinition.NodeType.EXTERNAL, 7, 8));

        NodeOutput.Data memory output = ExternalNode.process(new NodeOutput.Data[](0), _params(address(externalNode)));

        assertEq(output.price, 2000e18);
        assertEq(output.timestamp, TIMESTAMP);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.EXTERNAL));
        assertEq(output.additionalParam1, 7);
        assertEq(output.additionalParam2, 8);
    }

    function test_Process_ReplacesReturnedNodeTypeWithExternal() public {
        externalNode.setOutput(NodeOutput.Data(2000e18, TIMESTAMP, NodeDefinition.NodeType.CONSTANT, 0, 0));

        NodeOutput.Data memory output = ExternalNode.process(new NodeOutput.Data[](0), _params(address(externalNode)));

        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.EXTERNAL));
    }

    function test_Process_ReplacesReturnedNoneNodeTypeWithExternal() public {
        externalNode.setOutput(NodeOutput.Data(2000e18, TIMESTAMP, NodeDefinition.NodeType.NONE, 0, 0));

        NodeOutput.Data memory output = ExternalNode.process(new NodeOutput.Data[](0), _params(address(externalNode)));

        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.EXTERNAL));
    }

    function test_Process_ForwardsParentOutputsInOrder() public {
        NodeOutput.Data[] memory parentNodeOutputs = _parentOutputs(3e18, 300, 2e18, 200);
        bytes memory parameters = _params(address(externalNode));

        vm.expectCall(address(externalNode), abi.encodeCall(IExternalNode.process, (parentNodeOutputs, parameters)), 1);
        ExternalNode.process(parentNodeOutputs, parameters);
    }

    function test_Process_ForwardsParametersWithCustomBytesUnchanged() public {
        bytes memory parameters = _params(address(externalNode), hex"0102030405");

        vm.expectCall(
            address(externalNode), abi.encodeCall(IExternalNode.process, (new NodeOutput.Data[](0), parameters)), 1
        );
        ExternalNode.process(new NodeOutput.Data[](0), parameters);
    }

    function test_Process_ReturnsProductOfParents() public view {
        NodeOutput.Data memory output =
            ExternalNode.process(_parentOutputs(3e18, 300, 2e18, 200), _params(address(productNode)));

        assertEq(output.price, 6e18);
        assertEq(output.timestamp, 200);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.EXTERNAL));
    }

    function test_Process_IgnoresReturnDataAboveOutputLength() public {
        NodeOutput.Data memory returned = NodeOutput.Data(2000e18, TIMESTAMP, NodeDefinition.NodeType.EXTERNAL, 0, 0);
        vm.mockCall(
            address(externalNode),
            abi.encodeWithSelector(IExternalNode.process.selector),
            abi.encodePacked(abi.encode(returned), new bytes(1024))
        );

        NodeOutput.Data memory output = ExternalNode.process(new NodeOutput.Data[](0), _params(address(externalNode)));

        assertEq(output.price, 2000e18);
        assertEq(output.timestamp, TIMESTAMP);
    }

    function test_Process_Revert_ExternalNodeReverts() public {
        externalNode.setShouldRevertOnProcess(true);

        vm.expectRevert(MockExternalNode.ProcessReverted.selector);
        this.process(new NodeOutput.Data[](0), _params(address(externalNode)));
    }

    function test_Process_Revert_ParentsMissing() public {
        vm.expectRevert(stdError.indexOOBError);
        this.process(new NodeOutput.Data[](0), _params(address(productNode)));
    }

    function test_Process_Revert_ReturnDataBelowOutputLength() public {
        vm.mockCall(address(externalNode), abi.encodeWithSelector(IExternalNode.process.selector), new bytes(159));

        vm.expectRevert();
        this.process(new NodeOutput.Data[](0), _params(address(externalNode)));
    }

    function test_Process_Revert_ReturnedNodeTypeOutOfRange() public {
        vm.mockCall(
            address(externalNode),
            abi.encodeWithSelector(IExternalNode.process.selector),
            abi.encode(2000e18, TIMESTAMP, type(uint8).max, 0, 0)
        );

        vm.expectRevert();
        this.process(new NodeOutput.Data[](0), _params(address(externalNode)));
    }

    function test_Process_Revert_ExternalNodeHasNoCode() public {
        vm.expectRevert();
        this.process(new NodeOutput.Data[](0), _params(makeAddr("eoa")));
    }

    // isValid()

    function test_IsValid_ReturnsTrueForParamsOf32Bytes() public view {
        assertTrue(ExternalNode.isValid(_definition(_params(address(externalNode)), 0)));
    }

    function test_IsValid_ReturnsTrueForParamsOf33Bytes() public view {
        assertTrue(ExternalNode.isValid(_definition(_params(address(externalNode), hex"00"), 0)));
    }

    function test_IsValid_ReturnsTrueForParamsWithCustomBytes() public view {
        assertTrue(ExternalNode.isValid(_definition(_params(address(externalNode), abi.encode(1e18, "custom")), 0)));
    }

    function test_IsValid_ReturnsTrueWithParents() public view {
        assertTrue(ExternalNode.isValid(_definition(_params(address(productNode)), 2)));
    }

    function test_IsValid_ForwardsNodeDefinitionUnchanged() public {
        NodeDefinition.Data memory nodeDefinition = _definition(_params(address(externalNode), hex"0102030405"), 2);

        vm.expectCall(address(externalNode), abi.encodeCall(IExternalNode.isValid, (nodeDefinition)), 1);
        ExternalNode.isValid(nodeDefinition);
    }

    function test_IsValid_ReturnsTrueForMaxAddress() public {
        address maxAddress = address(type(uint160).max);
        vm.etch(maxAddress, address(productNode).code);

        assertTrue(ExternalNode.isValid(_definition(_params(maxAddress), 2)));
    }

    function test_IsValid_IgnoresIsValidReturnDataAbove32Bytes() public {
        vm.mockCall(
            address(externalNode),
            abi.encodeWithSelector(IExternalNode.isValid.selector),
            abi.encodePacked(abi.encode(true), uint8(0))
        );

        assertTrue(ExternalNode.isValid(_definition(_params(address(externalNode)), 0)));
    }

    function test_IsValid_ReturnsFalseWhenParamsEmpty() public view {
        assertFalse(ExternalNode.isValid(_definition("", 0)));
    }

    function test_IsValid_ReturnsFalseWhenParamsBelow32Bytes() public view {
        bytes memory parameters = _params(address(externalNode));
        assembly {
            mstore(parameters, 31)
        }

        assertFalse(ExternalNode.isValid(_definition(parameters, 0)));
    }

    function test_IsValid_ReturnsFalseWhenExternalIsValidReturnsFalse() public {
        externalNode.setIsValid(false);

        assertFalse(ExternalNode.isValid(_definition(_params(address(externalNode)), 0)));
    }

    function test_IsValid_ReturnsFalseWhenParentCountRejectedByExternalNode() public view {
        assertFalse(ExternalNode.isValid(_definition(_params(address(productNode)), 1)));
    }

    function test_IsValid_ReturnsFalseForEOA() public {
        assertFalse(ExternalNode.isValid(_definition(_params(makeAddr("eoa")), 0)));
    }

    function test_IsValid_ReturnsFalseForZeroAddress() public view {
        assertFalse(ExternalNode.isValid(_definition(_params(address(0)), 0)));
    }

    function test_IsValid_ReturnsFalseForUndeployedContractAddress() public view {
        address undeployed = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));

        assertFalse(ExternalNode.isValid(_definition(_params(undeployed), 0)));
    }

    function test_IsValid_ReturnsFalseWithoutERC165() public {
        MockNoERC165ExternalNode noERC165Node = new MockNoERC165ExternalNode();

        assertFalse(ExternalNode.isValid(_definition(_params(address(noERC165Node)), 0)));
    }

    function test_IsValid_ReturnsFalseWhenSupportsInterfaceReverts() public {
        externalNode.setShouldRevertOnSupportsInterface(true);

        assertFalse(ExternalNode.isValid(_definition(_params(address(externalNode)), 0)));
    }

    function test_IsValid_ReturnsFalseWhenSupportsInterfaceClaimsEveryInterface() public {
        MockCatchAllERC165ExternalNode catchAllNode = new MockCatchAllERC165ExternalNode();

        assertFalse(ExternalNode.isValid(_definition(_params(address(catchAllNode)), 0)));
    }

    function test_IsValid_ReturnsFalseForOtherInterface() public {
        NodeManager nodeManager = new NodeManager();

        assertFalse(ExternalNode.isValid(_definition(_params(address(nodeManager)), 0)));
    }

    function test_IsValid_ReturnsFalseForIdentityPrecompile() public view {
        assertFalse(ExternalNode.isValid(_definition(_params(IDENTITY_PRECOMPILE), 0)));
    }

    function test_IsValid_Revert_AddressAboveMax() public {
        vm.expectRevert();
        this.isValid(_definition(abi.encode(uint256(type(uint160).max) + 1), 0));
    }

    function test_IsValid_Revert_ExternalIsValidReverts() public {
        externalNode.setShouldRevertOnIsValid(true);

        vm.expectRevert(MockExternalNode.IsValidReverted.selector);
        this.isValid(_definition(_params(address(externalNode)), 0));
    }

    function test_IsValid_Revert_ExternalIsValidWritesState() public {
        NodeManager nodeManager = NodeManager(Clones.clone(address(new NodeManager())));
        nodeManager.initialize(new NodeDefinition.Data[](0));
        MockReentrantExternalNode reentrantNode = new MockReentrantExternalNode(INodeManager(address(nodeManager)));

        vm.expectRevert();
        this.isValid(_definition(_params(address(reentrantNode)), 0));
    }

    function test_IsValid_Revert_IsValidReturnDataBelow32Bytes() public {
        vm.mockCall(address(externalNode), abi.encodeWithSelector(IExternalNode.isValid.selector), new bytes(31));

        vm.expectRevert();
        this.isValid(_definition(_params(address(externalNode)), 0));
    }

    function test_IsValid_Revert_IsValidReturnsNonBooleanWord() public {
        vm.mockCall(address(externalNode), abi.encodeWithSelector(IExternalNode.isValid.selector), abi.encode(2));

        vm.expectRevert();
        this.isValid(_definition(_params(address(externalNode)), 0));
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        external
        view
        returns (NodeOutput.Data memory)
    {
        return ExternalNode.process(parentNodeOutputs, parameters);
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

    function _parentOutputs(uint256 firstPrice, uint256 firstTimestamp, uint256 secondPrice, uint256 secondTimestamp)
        internal
        pure
        returns (NodeOutput.Data[] memory parentNodeOutputs)
    {
        parentNodeOutputs = new NodeOutput.Data[](2);
        parentNodeOutputs[0] = NodeOutput.Data(firstPrice, firstTimestamp, NodeDefinition.NodeType.CONSTANT, 0, 0);
        parentNodeOutputs[1] = NodeOutput.Data(secondPrice, secondTimestamp, NodeDefinition.NodeType.CONSTANT, 0, 0);
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
