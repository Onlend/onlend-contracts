// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {StalenessCircuitBreakerNode} from "src/oracle/node-manager/lib/nodes/StalenessCircuitBreakerNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

contract StalenessCircuitBreakerNodeTest is Test {
    uint256 internal constant NOW = 1000;
    uint256 internal constant TOLERANCE = 100;

    function setUp() public {
        vm.warp(NOW);
    }

    // process()

    function test_Process_ReturnsPrimaryWhenFresh() public view {
        NodeOutput.Data[] memory parents = new NodeOutput.Data[](1);
        parents[0] = _output(1e18, NOW);

        NodeOutput.Data memory output = this.process(parents, abi.encode(TOLERANCE));

        assertEq(output.price, 1e18);
        assertEq(output.timestamp, NOW);
    }

    function test_Process_ReturnsPrimaryWhenExactlyAtTolerance() public view {
        NodeOutput.Data[] memory parents = new NodeOutput.Data[](2);
        parents[0] = _output(1e18, NOW - TOLERANCE);
        parents[1] = _output(2e18, NOW);

        NodeOutput.Data memory output = this.process(parents, abi.encode(TOLERANCE));

        assertEq(output.price, 1e18);
        assertEq(output.timestamp, NOW - TOLERANCE);
    }

    function test_Process_ReturnsFallbackWhenPrimaryIsStale() public view {
        NodeOutput.Data[] memory parents = new NodeOutput.Data[](2);
        parents[0] = _output(1e18, NOW - TOLERANCE - 1);
        parents[1] = _output(2e18, 1);

        NodeOutput.Data memory output = this.process(parents, abi.encode(TOLERANCE));

        assertEq(output.price, 2e18);
        assertEq(output.timestamp, 1);
    }

    function test_Process_ReturnsPrimaryWhenToleranceEqualsTimestamp() public view {
        NodeOutput.Data[] memory parents = new NodeOutput.Data[](1);
        parents[0] = _output(1e18, 0);

        NodeOutput.Data memory output = this.process(parents, abi.encode(NOW));

        assertEq(output.price, 1e18);
        assertEq(output.timestamp, 0);
    }

    function test_Process_Revert_StaleWithoutFallback() public {
        NodeOutput.Data[] memory parents = new NodeOutput.Data[](1);
        parents[0] = _output(1e18, NOW - TOLERANCE - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                StalenessCircuitBreakerNode.StalenessToleranceExceeded.selector,
                NodeDefinition.NodeType.CONSTANT,
                NOW - TOLERANCE - 1
            )
        );
        this.process(parents, abi.encode(TOLERANCE));
    }

    // isValid()

    function test_IsValid_ReturnsTrueForOneParent() public view {
        assertTrue(StalenessCircuitBreakerNode.isValid(_definition(abi.encode(TOLERANCE), 1)));
    }

    function test_IsValid_ReturnsTrueForTwoParents() public view {
        assertTrue(StalenessCircuitBreakerNode.isValid(_definition(abi.encode(TOLERANCE), 2)));
    }

    function test_IsValid_ReturnsFalseWhenNoParents() public view {
        assertFalse(StalenessCircuitBreakerNode.isValid(_definition(abi.encode(TOLERANCE), 0)));
    }

    function test_IsValid_ReturnsFalseWhenThreeParents() public view {
        assertFalse(StalenessCircuitBreakerNode.isValid(_definition(abi.encode(TOLERANCE), 3)));
    }

    function test_IsValid_ReturnsFalseWhenParamsEmpty() public view {
        assertFalse(StalenessCircuitBreakerNode.isValid(_definition("", 1)));
    }

    function test_IsValid_ReturnsFalseWhenParamsAbove32Bytes() public view {
        assertFalse(StalenessCircuitBreakerNode.isValid(_definition(abi.encodePacked(TOLERANCE, uint8(0)), 1)));
    }

    function test_IsValid_ReturnsTrueWhenToleranceEqualsTimestamp() public view {
        assertTrue(StalenessCircuitBreakerNode.isValid(_definition(abi.encode(NOW), 1)));
    }

    function test_IsValid_ReturnsFalseWhenToleranceAboveTimestamp() public view {
        assertFalse(StalenessCircuitBreakerNode.isValid(_definition(abi.encode(NOW + 1), 1)));
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        external
        view
        returns (NodeOutput.Data memory)
    {
        return StalenessCircuitBreakerNode.process(parentNodeOutputs, parameters);
    }

    function _output(uint256 price, uint256 timestamp) internal pure returns (NodeOutput.Data memory) {
        return NodeOutput.Data(price, timestamp, NodeDefinition.NodeType.CONSTANT, 0, 0);
    }

    function _definition(bytes memory parameters, uint256 parentCount)
        internal
        pure
        returns (NodeDefinition.Data memory)
    {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.STALENESS_CIRCUIT_BREAKER,
            parameters: parameters,
            parents: new bytes32[](parentCount)
        });
    }
}
