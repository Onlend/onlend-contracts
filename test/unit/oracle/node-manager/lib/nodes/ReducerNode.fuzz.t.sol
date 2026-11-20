// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ReducerNode} from "src/oracle/node-manager/lib/nodes/ReducerNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

contract ReducerNodeFuzzTest is Test {
    uint256 internal constant MAX_PARENTS = 8;

    // process()

    function testFuzz_Process_RecentTimestampIsNotBelowAnyParent(
        uint128[MAX_PARENTS] memory prices,
        uint64[MAX_PARENTS] memory timestamps,
        uint256 count
    ) public pure {
        NodeOutput.Data[] memory parents = _outputs(prices, timestamps, count);

        NodeOutput.Data memory output = ReducerNode.process(parents, abi.encode(ReducerNode.Operation.RECENT));

        for (uint256 i; i < parents.length; ++i) {
            assertGe(output.timestamp, parents[i].timestamp);
        }
        _assertIsParent(output, parents);
    }

    function testFuzz_Process_MinPriceIsNotAboveAnyParent(
        uint128[MAX_PARENTS] memory prices,
        uint64[MAX_PARENTS] memory timestamps,
        uint256 count
    ) public pure {
        NodeOutput.Data[] memory parents = _outputs(prices, timestamps, count);

        NodeOutput.Data memory output = ReducerNode.process(parents, abi.encode(ReducerNode.Operation.MIN));

        for (uint256 i; i < parents.length; ++i) {
            assertLe(output.price, parents[i].price);
        }
        _assertIsParent(output, parents);
    }

    function testFuzz_Process_MaxPriceIsNotBelowAnyParent(
        uint128[MAX_PARENTS] memory prices,
        uint64[MAX_PARENTS] memory timestamps,
        uint256 count
    ) public pure {
        NodeOutput.Data[] memory parents = _outputs(prices, timestamps, count);

        NodeOutput.Data memory output = ReducerNode.process(parents, abi.encode(ReducerNode.Operation.MAX));

        for (uint256 i; i < parents.length; ++i) {
            assertGe(output.price, parents[i].price);
        }
        _assertIsParent(output, parents);
    }

    function testFuzz_Process_MeanIsBetweenMinAndMax(
        uint128[MAX_PARENTS] memory prices,
        uint64[MAX_PARENTS] memory timestamps,
        uint256 count
    ) public pure {
        NodeOutput.Data[] memory parents = _outputs(prices, timestamps, count);

        NodeOutput.Data memory output = ReducerNode.process(parents, abi.encode(ReducerNode.Operation.MEAN));

        _assertWithinParentPrices(output.price, parents);
        _assertOldestTimestamp(output, parents);
    }

    function testFuzz_Process_MeanOfEqualPricesIsThatPrice(
        uint128 price,
        uint64[MAX_PARENTS] memory timestamps,
        uint256 count
    ) public pure {
        uint128[MAX_PARENTS] memory prices;
        for (uint256 i; i < MAX_PARENTS; ++i) {
            prices[i] = price;
        }
        NodeOutput.Data[] memory parents = _outputs(prices, timestamps, count);

        NodeOutput.Data memory output = ReducerNode.process(parents, abi.encode(ReducerNode.Operation.MEAN));

        assertEq(output.price, price);
    }

    function testFuzz_Process_MedianIsBetweenMinAndMax(
        uint128[MAX_PARENTS] memory prices,
        uint64[MAX_PARENTS] memory timestamps,
        uint256 count
    ) public pure {
        NodeOutput.Data[] memory parents = _outputs(prices, timestamps, count);

        NodeOutput.Data memory output = ReducerNode.process(parents, abi.encode(ReducerNode.Operation.MEDIAN));

        _assertWithinParentPrices(output.price, parents);
    }

    function testFuzz_Process_MedianOfOddCountIsAParent(
        uint128[MAX_PARENTS] memory prices,
        uint64[MAX_PARENTS] memory timestamps,
        uint256 count
    ) public pure {
        count = bound(count, 1, (MAX_PARENTS - 1) / 2) * 2 + 1;
        NodeOutput.Data[] memory parents = _outputs(prices, timestamps, count);

        NodeOutput.Data memory output = ReducerNode.process(parents, abi.encode(ReducerNode.Operation.MEDIAN));

        _assertIsParent(output, parents);
    }

    function testFuzz_Process_MedianOfEvenCountIsComputed(
        uint128[MAX_PARENTS] memory prices,
        uint64[MAX_PARENTS] memory timestamps,
        uint256 count
    ) public pure {
        count = bound(count, 1, MAX_PARENTS / 2) * 2;
        NodeOutput.Data[] memory parents = _outputs(prices, timestamps, count);

        NodeOutput.Data memory output = ReducerNode.process(parents, abi.encode(ReducerNode.Operation.MEDIAN));

        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.REDUCER));
    }

    function testFuzz_Process_MulDecimalByOneKeepsPrice(uint128 price, uint64 firstTs, uint64 secondTs) public pure {
        NodeOutput.Data[] memory parents = new NodeOutput.Data[](2);
        parents[0] = _output(price, firstTs);
        parents[1] = _output(1e18, secondTs);

        NodeOutput.Data memory output = ReducerNode.process(parents, abi.encode(ReducerNode.Operation.MUL_DECIMAL));

        assertEq(output.price, price);
        _assertOldestTimestamp(output, parents);
    }

    function testFuzz_Process_DivDecimalByOneKeepsPrice(uint128 price, uint64 firstTs, uint64 secondTs) public pure {
        NodeOutput.Data[] memory parents = new NodeOutput.Data[](2);
        parents[0] = _output(price, firstTs);
        parents[1] = _output(1e18, secondTs);

        NodeOutput.Data memory output = ReducerNode.process(parents, abi.encode(ReducerNode.Operation.DIV_DECIMAL));

        assertEq(output.price, price);
        _assertOldestTimestamp(output, parents);
    }

    function testFuzz_Process_DivDecimalRevertsOnZeroDivisor(
        uint128[MAX_PARENTS] memory prices,
        uint64[MAX_PARENTS] memory timestamps,
        uint256 count,
        uint256 zeroIndex
    ) public {
        count = bound(count, 2, MAX_PARENTS);
        zeroIndex = bound(zeroIndex, 1, count - 1);
        for (uint256 i = 1; i < zeroIndex; ++i) {
            prices[i] = uint128(bound(prices[i], 1e18, type(uint128).max));
        }
        prices[zeroIndex] = 0;
        NodeOutput.Data[] memory parents = _outputs(prices, timestamps, count);

        vm.expectRevert(abi.encodeWithSelector(ReducerNode.DivisionByZero.selector, zeroIndex));
        this.process(parents, ReducerNode.Operation.DIV_DECIMAL);
    }

    // isValid()

    function testFuzz_IsValid_ReturnsTrueWhenValidParams(uint256 operation, uint256 parentCount) public pure {
        operation = bound(operation, 0, uint256(type(ReducerNode.Operation).max));
        parentCount = bound(parentCount, 2, 16);

        assertTrue(ReducerNode.isValid(_definition(abi.encode(operation), parentCount)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenOperationOutOfRange(uint256 operation) public pure {
        operation = bound(operation, uint256(type(ReducerNode.Operation).max) + 1, type(uint256).max);

        assertFalse(ReducerNode.isValid(_definition(abi.encode(operation), 2)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenFewerThanTwoParents(uint256 operation, uint256 parentCount) public pure {
        operation = bound(operation, 0, uint256(type(ReducerNode.Operation).max));
        parentCount = bound(parentCount, 0, 1);

        assertFalse(ReducerNode.isValid(_definition(abi.encode(operation), parentCount)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenParamsLengthNot32(bytes calldata parameters) public pure {
        vm.assume(parameters.length != 32);

        assertFalse(ReducerNode.isValid(_definition(parameters, 2)));
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function process(NodeOutput.Data[] memory parentNodeOutputs, ReducerNode.Operation operation)
        external
        pure
        returns (NodeOutput.Data memory)
    {
        return ReducerNode.process(parentNodeOutputs, abi.encode(operation));
    }

    function _assertIsParent(NodeOutput.Data memory output, NodeOutput.Data[] memory parents) internal pure {
        bool found;
        for (uint256 i; i < parents.length; ++i) {
            if (parents[i].price == output.price && parents[i].timestamp == output.timestamp) found = true;
        }
        assertTrue(found);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
    }

    function _assertWithinParentPrices(uint256 price, NodeOutput.Data[] memory parents) internal pure {
        uint256 min = type(uint256).max;
        uint256 max;
        for (uint256 i; i < parents.length; ++i) {
            if (parents[i].price < min) min = parents[i].price;
            if (parents[i].price > max) max = parents[i].price;
        }
        assertGe(price, min);
        assertLe(price, max);
    }

    function _assertOldestTimestamp(NodeOutput.Data memory output, NodeOutput.Data[] memory parents) internal pure {
        bool found;
        for (uint256 i; i < parents.length; ++i) {
            assertLe(output.timestamp, parents[i].timestamp);
            if (parents[i].timestamp == output.timestamp) found = true;
        }
        assertTrue(found);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.REDUCER));
    }

    function _outputs(uint128[MAX_PARENTS] memory prices, uint64[MAX_PARENTS] memory timestamps, uint256 count)
        internal
        pure
        returns (NodeOutput.Data[] memory outputs)
    {
        count = bound(count, 2, MAX_PARENTS);
        outputs = new NodeOutput.Data[](count);
        for (uint256 i; i < count; ++i) {
            outputs[i] = _output(prices[i], timestamps[i]);
        }
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
            nodeType: NodeDefinition.NodeType.REDUCER, parameters: parameters, parents: new bytes32[](parentCount)
        });
    }
}
