// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {SequencerUptimeNode} from "src/oracle/node-manager/lib/nodes/SequencerUptimeNode.sol";
import {IAggregatorV3} from "src/oracle/node-manager/interfaces/external/IAggregatorV3.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {MockAggregatorV3} from "../../../../../mocks/MockAggregatorV3.sol";

contract SequencerUptimeNodeTest is Test {
    uint256 internal constant NOW = 10_000;
    uint256 internal constant STARTED_AT = 5000;
    uint256 internal constant GRACE_PERIOD = 3600;

    MockAggregatorV3 internal feed;

    function setUp() public {
        vm.warp(NOW);
        feed = new MockAggregatorV3(0, 0, STARTED_AT);
    }

    // process()

    function test_Process_ReturnsParentOutputUnchangedWhenSequencerIsUp() public view {
        NodeOutput.Data memory output = SequencerUptimeNode.process(_parentOutputs(), _params(GRACE_PERIOD));

        assertEq(output.price, 2000e18);
        assertEq(output.timestamp, 800);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.AGGREGATOR_V3));
        assertEq(output.additionalParam1, 7);
        assertEq(output.additionalParam2, 8);
    }

    function test_Process_ReturnsParentOutputWhenGracePeriodEndsNow() public {
        feed.setRoundData(1, 0, NOW - GRACE_PERIOD, NOW - GRACE_PERIOD, 1);

        NodeOutput.Data memory output = SequencerUptimeNode.process(_parentOutputs(), _params(GRACE_PERIOD));

        assertEq(output.price, 2000e18);
    }

    function test_Process_ReturnsParentOutputWhenStartedNowWithZeroGracePeriod() public {
        feed.setRoundData(1, 0, NOW, NOW, 1);

        NodeOutput.Data memory output = SequencerUptimeNode.process(_parentOutputs(), _params(0));

        assertEq(output.price, 2000e18);
    }

    function test_Process_ReturnsParentOutputWhenStartedAtIsZero() public {
        feed.setRoundData(0, 0, 0, 0, 0);

        NodeOutput.Data memory output = SequencerUptimeNode.process(_parentOutputs(), _params(GRACE_PERIOD));

        assertEq(output.price, 2000e18);
    }

    function test_Process_Revert_SequencerDown() public {
        feed.setRoundData(2, 1, STARTED_AT, STARTED_AT, 2);

        vm.expectRevert(abi.encodeWithSelector(SequencerUptimeNode.SequencerDown.selector, address(feed)));
        this.process(_parentOutputs(), _params(GRACE_PERIOD));
    }

    function test_Process_Revert_SequencerDownWhenAnswerAboveOne() public {
        feed.setRoundData(2, 2, STARTED_AT, STARTED_AT, 2);

        vm.expectRevert(abi.encodeWithSelector(SequencerUptimeNode.SequencerDown.selector, address(feed)));
        this.process(_parentOutputs(), _params(GRACE_PERIOD));
    }

    function test_Process_Revert_SequencerDownWhenAnswerNegative() public {
        feed.setRoundData(2, -1, STARTED_AT, STARTED_AT, 2);

        vm.expectRevert(abi.encodeWithSelector(SequencerUptimeNode.SequencerDown.selector, address(feed)));
        this.process(_parentOutputs(), _params(GRACE_PERIOD));
    }

    function test_Process_Revert_SequencerDownTakesPrecedenceOverGracePeriod() public {
        feed.setRoundData(2, 1, NOW, NOW, 2);

        vm.expectRevert(abi.encodeWithSelector(SequencerUptimeNode.SequencerDown.selector, address(feed)));
        this.process(_parentOutputs(), _params(GRACE_PERIOD));
    }

    function test_Process_Revert_GracePeriodNotOver() public {
        feed.setRoundData(1, 0, NOW - GRACE_PERIOD + 1, NOW - GRACE_PERIOD + 1, 1);

        vm.expectRevert(abi.encodeWithSelector(SequencerUptimeNode.GracePeriodNotOver.selector, address(feed)));
        this.process(_parentOutputs(), _params(GRACE_PERIOD));
    }

    function test_Process_Revert_StartedAtIsInFuture() public {
        feed.setRoundData(1, 0, NOW + 1, NOW + 1, 1);

        vm.expectRevert(stdError.arithmeticError);
        this.process(_parentOutputs(), _params(0));
    }

    function test_Process_Revert_FeedReverts() public {
        feed.setShouldRevertOnLatestRoundData(true);

        vm.expectRevert(MockAggregatorV3.LatestRoundDataReverted.selector);
        this.process(_parentOutputs(), _params(GRACE_PERIOD));
    }

    function test_Process_Revert_FeedHasNoCode() public {
        vm.expectRevert();
        this.process(_parentOutputs(), abi.encode(makeAddr("eoa"), GRACE_PERIOD));
    }

    // isValid()

    function test_IsValid_ReturnsTrueForFeedWithOneParent() public view {
        assertTrue(SequencerUptimeNode.isValid(_definition(_params(GRACE_PERIOD), 1)));
    }

    function test_IsValid_ReturnsTrueForZeroGracePeriod() public view {
        assertTrue(SequencerUptimeNode.isValid(_definition(_params(0), 1)));
    }

    function test_IsValid_ReturnsTrueForMaxGracePeriod() public view {
        assertTrue(SequencerUptimeNode.isValid(_definition(_params(type(uint256).max), 1)));
    }

    function test_IsValid_ReturnsTrueWhileSequencerIsDown() public {
        feed.setRoundData(2, 1, STARTED_AT, STARTED_AT, 2);

        assertTrue(SequencerUptimeNode.isValid(_definition(_params(GRACE_PERIOD), 1)));
    }

    function test_IsValid_ReturnsTrueWithinGracePeriod() public {
        feed.setRoundData(1, 0, NOW, NOW, 1);

        assertTrue(SequencerUptimeNode.isValid(_definition(_params(GRACE_PERIOD), 1)));
    }

    function test_IsValid_ReturnsFalseWhenNoParents() public view {
        assertFalse(SequencerUptimeNode.isValid(_definition(_params(GRACE_PERIOD), 0)));
    }

    function test_IsValid_ReturnsFalseWhenTwoParents() public view {
        assertFalse(SequencerUptimeNode.isValid(_definition(_params(GRACE_PERIOD), 2)));
    }

    function test_IsValid_ReturnsFalseWhenParamsEmpty() public view {
        assertFalse(SequencerUptimeNode.isValid(_definition("", 1)));
    }

    function test_IsValid_ReturnsFalseWhenParamsBelow64Bytes() public view {
        assertFalse(SequencerUptimeNode.isValid(_definition(abi.encode(address(feed)), 1)));
    }

    function test_IsValid_ReturnsFalseWhenParamsAbove64Bytes() public view {
        assertFalse(SequencerUptimeNode.isValid(_definition(abi.encodePacked(_params(GRACE_PERIOD), uint8(0)), 1)));
    }

    function test_IsValid_ReturnsTrueForMaxAddress() public {
        address maxAddress = address(type(uint160).max);
        vm.etch(maxAddress, address(feed).code);

        assertTrue(SequencerUptimeNode.isValid(_definition(abi.encode(maxAddress, GRACE_PERIOD), 1)));
    }

    function test_IsValid_Revert_AddressAboveMax() public {
        vm.expectRevert();
        this.isValid(_definition(abi.encode(uint256(type(uint160).max) + 1, GRACE_PERIOD), 1));
    }

    function test_IsValid_Revert_ZeroFeed() public {
        vm.expectRevert();
        this.isValid(_definition(abi.encode(address(0), GRACE_PERIOD), 1));
    }

    function test_IsValid_Revert_FeedHasNoCode() public {
        vm.expectRevert();
        this.isValid(_definition(abi.encode(makeAddr("eoa"), GRACE_PERIOD), 1));
    }

    function test_IsValid_Revert_LatestRoundDataReverts() public {
        feed.setShouldRevertOnLatestRoundData(true);

        vm.expectRevert(MockAggregatorV3.LatestRoundDataReverted.selector);
        this.isValid(_definition(_params(GRACE_PERIOD), 1));
    }

    function test_IsValid_Revert_LatestRoundDataReturnDataBelow160Bytes() public {
        vm.mockCall(address(feed), abi.encodeCall(IAggregatorV3.latestRoundData, ()), new bytes(159));

        vm.expectRevert();
        this.isValid(_definition(_params(GRACE_PERIOD), 1));
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        external
        view
        returns (NodeOutput.Data memory)
    {
        return SequencerUptimeNode.process(parentNodeOutputs, parameters);
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function isValid(NodeDefinition.Data memory nodeDefinition) external view returns (bool) {
        return SequencerUptimeNode.isValid(nodeDefinition);
    }

    function _params(uint256 gracePeriod) internal view returns (bytes memory) {
        return abi.encode(address(feed), gracePeriod);
    }

    function _parentOutputs() internal pure returns (NodeOutput.Data[] memory parentNodeOutputs) {
        parentNodeOutputs = new NodeOutput.Data[](1);
        parentNodeOutputs[0] = NodeOutput.Data(2000e18, 800, NodeDefinition.NodeType.AGGREGATOR_V3, 7, 8);
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
