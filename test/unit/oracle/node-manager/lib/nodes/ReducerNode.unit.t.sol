// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {ReducerNode} from "src/oracle/node-manager/lib/nodes/ReducerNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

contract ReducerNodeTest is Test {
    // process()

    function test_Process_RecentReturnsLatestParent() public view {
        NodeOutput.Data[] memory parents = _outputs(_output(1e18, 10), _output(2e18, 30), _output(3e18, 20));

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.RECENT);

        _assertParent(output, 2e18, 30);
    }

    function test_Process_RecentReturnsFirstParentOnTie() public view {
        NodeOutput.Data[] memory parents = _outputs(_output(1e18, 10), _output(2e18, 10));

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.RECENT);

        _assertParent(output, 1e18, 10);
    }

    function test_Process_RecentReturnsFirstParentWhenAllTimestampsZero() public view {
        NodeOutput.Data[] memory parents = _outputs(_output(1e18, 0), _output(2e18, 0));

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.RECENT);

        _assertParent(output, 1e18, 0);
    }

    function test_Process_MinReturnsLowestPriceParent() public view {
        NodeOutput.Data[] memory parents = _outputs(_output(2e18, 10), _output(1e18, 30), _output(3e18, 20));

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.MIN);

        _assertParent(output, 1e18, 30);
    }

    function test_Process_MinReturnsFirstParentOnTie() public view {
        NodeOutput.Data[] memory parents = _outputs(_output(1e18, 10), _output(1e18, 20));

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.MIN);

        _assertParent(output, 1e18, 10);
    }

    function test_Process_MaxReturnsHighestPriceParent() public view {
        NodeOutput.Data[] memory parents = _outputs(_output(2e18, 10), _output(3e18, 30), _output(1e18, 20));

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.MAX);

        _assertParent(output, 3e18, 30);
    }

    function test_Process_MaxReturnsFirstParentOnTie() public view {
        NodeOutput.Data[] memory parents = _outputs(_output(1e18, 10), _output(1e18, 20));

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.MAX);

        _assertParent(output, 1e18, 10);
    }

    function test_Process_MeanReturnsAveragePriceWithOldestTimestamp() public view {
        NodeOutput.Data[] memory parents = _outputs(_output(1e18, 20), _output(2e18, 30), _output(3e18, 10));

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.MEAN);

        _assertComputed(output, 2e18, 10);
    }

    function test_Process_MeanRoundsDown() public view {
        NodeOutput.Data[] memory parents = _outputs(_output(1, 10), _output(2, 10));

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.MEAN);

        _assertComputed(output, 1, 10);
    }

    function test_Process_Revert_MeanSumOverflows() public {
        NodeOutput.Data[] memory parents = _outputs(_output(type(uint256).max, 10), _output(1, 10));

        vm.expectRevert(stdError.arithmeticError);
        this.process(parents, ReducerNode.Operation.MEAN);
    }

    function test_Process_MedianReturnsMiddleParentForOddCount() public view {
        NodeOutput.Data[] memory parents = _outputs(_output(3e18, 10), _output(1e18, 20), _output(2e18, 30));

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.MEDIAN);

        _assertParent(output, 2e18, 30);
    }

    function test_Process_MedianReturnsMeanOfMiddleParentsForEvenCount() public view {
        NodeOutput.Data[] memory parents = new NodeOutput.Data[](4);
        parents[0] = _output(4e18, 1);
        parents[1] = _output(1e18, 2);
        parents[2] = _output(3e18, 7);
        parents[3] = _output(2e18, 8);

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.MEDIAN);

        // The middle parents are 2e18 (ts 8) and 3e18 (ts 7); the outer parents' older timestamps are ignored.
        _assertComputed(output, 2.5e18, 7);
    }

    function test_Process_MedianDoesNotReorderParents() public pure {
        NodeOutput.Data[] memory parents = _outputs(_output(3e18, 10), _output(1e18, 20), _output(2e18, 30));

        ReducerNode.process(parents, abi.encode(ReducerNode.Operation.MEDIAN));

        assertEq(parents[0].price, 3e18);
        assertEq(parents[1].price, 1e18);
        assertEq(parents[2].price, 2e18);
    }

    function test_Process_MulDecimalMultipliesPrices() public view {
        NodeOutput.Data[] memory parents = _outputs(_output(2e18, 20), _output(3e18, 10), _output(0.5e18, 30));

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.MUL_DECIMAL);

        _assertComputed(output, 3e18, 10);
    }

    function test_Process_Revert_MulDecimalOverflows() public {
        NodeOutput.Data[] memory parents = _outputs(_output(type(uint256).max, 10), _output(2e18, 10));

        vm.expectRevert(stdError.arithmeticError);
        this.process(parents, ReducerNode.Operation.MUL_DECIMAL);
    }

    function test_Process_DivDecimalDividesPrices() public view {
        NodeOutput.Data[] memory parents = _outputs(_output(6e18, 20), _output(2e18, 10), _output(1.5e18, 30));

        NodeOutput.Data memory output = this.process(parents, ReducerNode.Operation.DIV_DECIMAL);

        _assertComputed(output, 2e18, 10);
    }

    function test_Process_Revert_DivDecimalByZero() public {
        NodeOutput.Data[] memory parents = _outputs(_output(6e18, 10), _output(2e18, 10), _output(0, 10));

        vm.expectRevert(abi.encodeWithSelector(ReducerNode.DivisionByZero.selector, 2));
        this.process(parents, ReducerNode.Operation.DIV_DECIMAL);
    }

    function test_Process_Revert_DivDecimalOverflows() public {
        NodeOutput.Data[] memory parents = _outputs(_output(type(uint256).max, 10), _output(0.5e18, 10));

        vm.expectRevert(stdError.arithmeticError);
        this.process(parents, ReducerNode.Operation.DIV_DECIMAL);
    }

    function test_Process_Revert_OperationOutOfRange() public {
        NodeOutput.Data[] memory parents = _outputs(_output(1e18, 10), _output(2e18, 10));
        bytes memory parameters = abi.encode(uint256(type(ReducerNode.Operation).max) + 1);

        vm.expectRevert();
        this.processRaw(parents, parameters);
    }

    // @dev UnsupportedOperation is unreachable while every Operation has reduction logic — `abi.decode` into
    // Operation already reverts on an out-of-range value, as test_Process_Revert_OperationOutOfRange shows.

    // isValid()

    function test_IsValid_ReturnsTrueForFirstOperation() public pure {
        assertTrue(ReducerNode.isValid(_definition(abi.encode(ReducerNode.Operation.RECENT), 2)));
    }

    function test_IsValid_ReturnsTrueForLastOperation() public pure {
        assertTrue(ReducerNode.isValid(_definition(abi.encode(ReducerNode.Operation.DIV_DECIMAL), 2)));
    }

    function test_IsValid_ReturnsFalseWhenOperationOutOfRange() public pure {
        assertFalse(ReducerNode.isValid(_definition(abi.encode(uint256(ReducerNode.Operation.DIV_DECIMAL) + 1), 2)));
    }

    function test_IsValid_ReturnsTrueForManyParents() public pure {
        assertTrue(ReducerNode.isValid(_definition(abi.encode(ReducerNode.Operation.MEDIAN), 5)));
    }

    function test_IsValid_ReturnsFalseWhenOneParent() public pure {
        assertFalse(ReducerNode.isValid(_definition(abi.encode(ReducerNode.Operation.MEDIAN), 1)));
    }

    function test_IsValid_ReturnsFalseWhenNoParents() public pure {
        assertFalse(ReducerNode.isValid(_definition(abi.encode(ReducerNode.Operation.MEDIAN), 0)));
    }

    function test_IsValid_ReturnsFalseWhenParamsEmpty() public pure {
        assertFalse(ReducerNode.isValid(_definition("", 2)));
    }

    function test_IsValid_ReturnsFalseWhenParamsAbove32Bytes() public pure {
        assertFalse(ReducerNode.isValid(_definition(abi.encodePacked(uint256(0), uint8(0)), 2)));
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function process(NodeOutput.Data[] memory parentNodeOutputs, ReducerNode.Operation operation)
        external
        pure
        returns (NodeOutput.Data memory)
    {
        return ReducerNode.process(parentNodeOutputs, abi.encode(operation));
    }

    /// @dev External wrapper taking raw parameters, to pass values that do not fit Operation.
    function processRaw(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        external
        pure
        returns (NodeOutput.Data memory)
    {
        return ReducerNode.process(parentNodeOutputs, parameters);
    }

    function _assertParent(NodeOutput.Data memory output, uint256 price, uint256 timestamp) internal pure {
        assertEq(output.price, price);
        assertEq(output.timestamp, timestamp);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.CONSTANT));
    }

    function _assertComputed(NodeOutput.Data memory output, uint256 price, uint256 timestamp) internal pure {
        assertEq(output.price, price);
        assertEq(output.timestamp, timestamp);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.REDUCER));
        assertEq(output.additionalParam1, 0);
        assertEq(output.additionalParam2, 0);
    }

    function _output(uint256 price, uint256 timestamp) internal pure returns (NodeOutput.Data memory) {
        return NodeOutput.Data(price, timestamp, NodeDefinition.NodeType.CONSTANT, 0, 0);
    }

    function _outputs(NodeOutput.Data memory first, NodeOutput.Data memory second)
        internal
        pure
        returns (NodeOutput.Data[] memory outputs)
    {
        outputs = new NodeOutput.Data[](2);
        outputs[0] = first;
        outputs[1] = second;
    }

    function _outputs(NodeOutput.Data memory first, NodeOutput.Data memory second, NodeOutput.Data memory third)
        internal
        pure
        returns (NodeOutput.Data[] memory outputs)
    {
        outputs = new NodeOutput.Data[](3);
        outputs[0] = first;
        outputs[1] = second;
        outputs[2] = third;
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
