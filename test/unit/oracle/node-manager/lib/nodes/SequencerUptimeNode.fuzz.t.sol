// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {SequencerUptimeNode} from "src/oracle/node-manager/lib/nodes/SequencerUptimeNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {MockAggregatorV3} from "../../../../../mocks/MockAggregatorV3.sol";

contract SequencerUptimeNodeFuzzTest is Test {
    uint256 internal constant NOW = 1_000_000_000;
    /// @dev Upper bound on fuzzed parent counts; any count above one is invalid.
    uint256 internal constant MAX_PARENTS = 16;

    MockAggregatorV3 internal feed;

    function setUp() public {
        vm.warp(NOW);
        feed = new MockAggregatorV3(0, 0, 1);
    }

    // process()

    function testFuzz_Process_ReturnsParentOutputUnchangedOnceGracePeriodIsOver(
        uint256 price,
        uint256 timestamp,
        uint8 nodeType,
        uint256 additionalParam1,
        uint256 additionalParam2,
        uint256 gracePeriod,
        uint256 startedAt
    ) public {
        nodeType = uint8(bound(nodeType, 0, uint8(type(NodeDefinition.NodeType).max)));
        gracePeriod = bound(gracePeriod, 0, NOW);
        startedAt = bound(startedAt, 0, NOW - gracePeriod);
        feed.setRoundData(1, 0, startedAt, startedAt, 1);
        NodeOutput.Data[] memory parentNodeOutputs = new NodeOutput.Data[](1);
        parentNodeOutputs[0] =
            NodeOutput.Data(price, timestamp, NodeDefinition.NodeType(nodeType), additionalParam1, additionalParam2);

        NodeOutput.Data memory output = SequencerUptimeNode.process(parentNodeOutputs, _params(gracePeriod));

        assertEq(output.price, price);
        assertEq(output.timestamp, timestamp);
        assertEq(uint8(output.nodeType), nodeType);
        assertEq(output.additionalParam1, additionalParam1);
        assertEq(output.additionalParam2, additionalParam2);
    }

    function testFuzz_Process_RevertsWithinGracePeriod(uint256 gracePeriod, uint256 elapsed) public {
        gracePeriod = bound(gracePeriod, 1, type(uint256).max);
        elapsed = bound(elapsed, 0, Math.min(gracePeriod - 1, NOW));
        feed.setRoundData(1, 0, NOW - elapsed, NOW - elapsed, 1);

        vm.expectRevert(abi.encodeWithSelector(SequencerUptimeNode.GracePeriodNotOver.selector, address(feed)));
        this.process(_parentOutputs(), _params(gracePeriod));
    }

    function testFuzz_Process_RevertsWhenStartedAtIsInFuture(uint256 gracePeriod, uint256 startedAt) public {
        startedAt = bound(startedAt, NOW + 1, type(uint256).max);
        feed.setRoundData(1, 0, startedAt, startedAt, 1);

        vm.expectRevert(stdError.arithmeticError);
        this.process(_parentOutputs(), _params(gracePeriod));
    }

    function testFuzz_Process_RevertsWhenAnswerIsPositive(int256 answer, uint256 startedAt, uint256 gracePeriod)
        public
    {
        answer = bound(answer, 1, type(int256).max);
        feed.setRoundData(1, answer, startedAt, startedAt, 1);

        vm.expectRevert(abi.encodeWithSelector(SequencerUptimeNode.SequencerDown.selector, address(feed)));
        this.process(_parentOutputs(), _params(gracePeriod));
    }

    function testFuzz_Process_RevertsWhenAnswerIsNegative(int256 answer, uint256 startedAt, uint256 gracePeriod)
        public
    {
        answer = bound(answer, type(int256).min, -1);
        feed.setRoundData(1, answer, startedAt, startedAt, 1);

        vm.expectRevert(abi.encodeWithSelector(SequencerUptimeNode.SequencerDown.selector, address(feed)));
        this.process(_parentOutputs(), _params(gracePeriod));
    }

    // isValid()

    function testFuzz_IsValid_ReturnsTrueWhateverSequencerStatus(int256 answer, uint256 startedAt, uint256 gracePeriod)
        public
    {
        feed.setRoundData(1, answer, startedAt, startedAt, 1);

        assertTrue(SequencerUptimeNode.isValid(_definition(_params(gracePeriod), 1)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenMoreThanOneParent(uint256 parentCount) public view {
        parentCount = bound(parentCount, 2, MAX_PARENTS);

        assertFalse(SequencerUptimeNode.isValid(_definition(_params(0), parentCount)));
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        external
        view
        returns (NodeOutput.Data memory)
    {
        return SequencerUptimeNode.process(parentNodeOutputs, parameters);
    }

    function _params(uint256 gracePeriod) internal view returns (bytes memory) {
        return abi.encode(address(feed), gracePeriod);
    }

    function _parentOutputs() internal pure returns (NodeOutput.Data[] memory parentNodeOutputs) {
        parentNodeOutputs = new NodeOutput.Data[](1);
        parentNodeOutputs[0] = NodeOutput.Data(2000e18, 800, NodeDefinition.NodeType.AGGREGATOR_V3, 0, 0);
    }

    function _definition(bytes memory parameters, uint256 parentCount)
        internal
        pure
        returns (NodeDefinition.Data memory)
    {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.SEQUENCER_UPTIME,
            parameters: parameters,
            parents: new bytes32[](parentCount)
        });
    }
}
