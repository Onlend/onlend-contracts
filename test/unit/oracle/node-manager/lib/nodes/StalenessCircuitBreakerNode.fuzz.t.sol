// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {StalenessCircuitBreakerNode} from "src/oracle/node-manager/lib/nodes/StalenessCircuitBreakerNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

contract StalenessCircuitBreakerNodeFuzzTest is Test {
    // process()

    function testFuzz_Process_ReturnsPrimaryWhenFresh(uint256 now_, uint256 tolerance, uint256 primaryTs) public {
        now_ = bound(now_, 1, type(uint64).max);
        tolerance = bound(tolerance, 0, now_);
        primaryTs = bound(primaryTs, now_ - tolerance, type(uint256).max);
        vm.warp(now_);
        NodeOutput.Data[] memory parents = new NodeOutput.Data[](2);
        parents[0] = _output(1e18, primaryTs);
        parents[1] = _output(2e18, now_);

        NodeOutput.Data memory output = this.process(parents, abi.encode(tolerance));

        assertEq(output.price, 1e18);
        assertEq(output.timestamp, primaryTs);
    }

    function testFuzz_Process_ReturnsFallbackWhenStale(
        uint256 now_,
        uint256 tolerance,
        uint256 primaryTs,
        uint256 fallbackTs
    ) public {
        now_ = bound(now_, 1, type(uint64).max);
        tolerance = bound(tolerance, 0, now_ - 1);
        primaryTs = bound(primaryTs, 0, now_ - tolerance - 1);
        vm.warp(now_);
        NodeOutput.Data[] memory parents = new NodeOutput.Data[](2);
        parents[0] = _output(1e18, primaryTs);
        parents[1] = _output(2e18, fallbackTs);

        NodeOutput.Data memory output = this.process(parents, abi.encode(tolerance));

        assertEq(output.price, 2e18);
        assertEq(output.timestamp, fallbackTs);
    }

    function testFuzz_Process_RevertsWhenStaleWithoutFallback(uint256 now_, uint256 tolerance, uint256 primaryTs)
        public
    {
        now_ = bound(now_, 1, type(uint64).max);
        tolerance = bound(tolerance, 0, now_ - 1);
        primaryTs = bound(primaryTs, 0, now_ - tolerance - 1);
        vm.warp(now_);
        NodeOutput.Data[] memory parents = new NodeOutput.Data[](1);
        parents[0] = _output(1e18, primaryTs);

        vm.expectRevert(
            abi.encodeWithSelector(
                StalenessCircuitBreakerNode.StalenessToleranceExceeded.selector,
                NodeDefinition.NodeType.CONSTANT,
                primaryTs
            )
        );
        this.process(parents, abi.encode(tolerance));
    }

    // isValid()

    function testFuzz_IsValid_ReturnsTrueWhenValidParams(uint256 now_, uint256 tolerance, uint256 parentCount) public {
        now_ = bound(now_, 0, type(uint64).max);
        tolerance = bound(tolerance, 0, now_);
        parentCount = bound(parentCount, 1, 2);
        vm.warp(now_);

        assertTrue(StalenessCircuitBreakerNode.isValid(_definition(abi.encode(tolerance), parentCount)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenToleranceAboveTimestamp(uint256 now_, uint256 tolerance) public {
        now_ = bound(now_, 0, type(uint64).max);
        tolerance = bound(tolerance, now_ + 1, type(uint256).max);
        vm.warp(now_);

        assertFalse(StalenessCircuitBreakerNode.isValid(_definition(abi.encode(tolerance), 1)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenTooManyParents(uint256 tolerance, uint256 parentCount) public view {
        tolerance = bound(tolerance, 0, block.timestamp);
        parentCount = bound(parentCount, 3, 16);

        assertFalse(StalenessCircuitBreakerNode.isValid(_definition(abi.encode(tolerance), parentCount)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenParamsLengthNot32(bytes calldata parameters) public view {
        vm.assume(parameters.length != 32);

        assertFalse(StalenessCircuitBreakerNode.isValid(_definition(parameters, 1)));
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
