// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {AggregatorV3Node} from "src/oracle/node-manager/lib/nodes/AggregatorV3Node.sol";
import {IAggregatorV3} from "src/oracle/node-manager/interfaces/external/IAggregatorV3.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {MockAggregatorV3} from "../../../../../mocks/MockAggregatorV3.sol";

contract AggregatorV3NodeTest is Test {
    uint256 internal constant NOW = 1000;
    uint256 internal constant UPDATED_AT = 900;

    MockAggregatorV3 internal aggregator;

    function setUp() public {
        vm.warp(NOW);
        aggregator = new MockAggregatorV3(8, 2000e8, UPDATED_AT);
    }

    // process()

    function test_Process_ReturnsCorrectOutput() public view {
        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, 2000e18);
        assertEq(output.timestamp, UPDATED_AT);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.AGGREGATOR_V3));
        assertEq(output.additionalParam1, 0);
        assertEq(output.additionalParam2, 0);
    }

    function test_Process_ScalesUpFromZeroDecimals() public {
        aggregator.setDecimals(0);
        aggregator.setAnswer(2000, UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, 2000e18);
    }

    function test_Process_ScalesUpFromSeventeenDecimals() public {
        aggregator.setDecimals(17);
        aggregator.setAnswer(2000e17, UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, 2000e18);
    }

    function test_Process_KeepsAnswerAtEighteenDecimals() public {
        aggregator.setDecimals(18);
        aggregator.setAnswer(2000e18 + 1, UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, 2000e18 + 1);
    }

    function test_Process_ScalesDownFromNineteenDecimals() public {
        aggregator.setDecimals(19);
        aggregator.setAnswer(2000e19, UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, 2000e18);
    }

    function test_Process_ScalesDownFromThirtySixDecimals() public {
        aggregator.setDecimals(36);
        aggregator.setAnswer(2000e36, UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, 2000e18);
    }

    function test_Process_RoundsDownWhenScalingDown() public {
        aggregator.setDecimals(20);
        aggregator.setAnswer(2000e20 + 99, UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, 2000e18);
    }

    function test_Process_ReturnsZeroWhenAnswerScalesDownToZero() public {
        aggregator.setDecimals(20);
        aggregator.setAnswer(99, UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, 0);
    }

    function test_Process_ReturnsSmallestPriceWhenScalingDownExactlyOneUnit() public {
        aggregator.setDecimals(20);
        aggregator.setAnswer(100, UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, 1);
    }

    function test_Process_ReturnsZeroForZeroAnswer() public {
        aggregator.setAnswer(0, UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, 0);
        assertEq(output.timestamp, UPDATED_AT);
    }

    function test_Process_AcceptsUpdatedAtOfOne() public {
        aggregator.setAnswer(2000e8, 1);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.timestamp, 1);
    }

    function test_Process_ReturnsFutureUpdatedAtUnchanged() public {
        aggregator.setAnswer(2000e8, NOW + 1);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.timestamp, NOW + 1);
    }

    function test_Process_IgnoresAnsweredInEarlierRound() public {
        aggregator.setRoundData(5, 2000e8, UPDATED_AT, UPDATED_AT, 4);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, 2000e18);
        assertEq(output.timestamp, UPDATED_AT);
    }

    function test_Process_Revert_NegativeAnswer() public {
        aggregator.setAnswer(-1, UPDATED_AT);

        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedIntToUint.selector, -1));
        this.process(abi.encode(address(aggregator)));
    }

    function test_Process_Revert_ZeroUpdatedAt() public {
        aggregator.setRoundData(5, 2000e8, UPDATED_AT, 0, 5);

        vm.expectRevert(abi.encodeWithSelector(AggregatorV3Node.ZeroUpdatedAt.selector, address(aggregator)));
        this.process(abi.encode(address(aggregator)));
    }

    function test_Process_ScalesDownFromNinetyFiveDecimals() public {
        aggregator.setDecimals(95);
        aggregator.setAnswer(type(int256).max, UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, uint256(type(int256).max) / 1e77);
    }

    function test_Process_Revert_ScalingFactorOverflows() public {
        aggregator.setDecimals(96);

        vm.expectRevert(stdError.arithmeticError);
        this.process(abi.encode(address(aggregator)));
    }

    function test_Process_Revert_ScaledPriceOverflows() public {
        aggregator.setDecimals(0);
        aggregator.setAnswer(type(int256).max, UPDATED_AT);

        vm.expectRevert(stdError.arithmeticError);
        this.process(abi.encode(address(aggregator)));
    }

    function test_Process_Revert_LatestRoundDataReverts() public {
        aggregator.setShouldRevertOnLatestRoundData(true);

        vm.expectRevert(MockAggregatorV3.LatestRoundDataReverted.selector);
        this.process(abi.encode(address(aggregator)));
    }

    function test_Process_Revert_DecimalsReverts() public {
        aggregator.setShouldRevertOnDecimals(true);

        vm.expectRevert(MockAggregatorV3.DecimalsReverted.selector);
        this.process(abi.encode(address(aggregator)));
    }

    function test_Process_Revert_AggregatorHasNoCode() public {
        vm.expectRevert();
        this.process(abi.encode(makeAddr("eoa")));
    }

    // isValid()

    function test_IsValid_ReturnsTrueForAggregator() public view {
        assertTrue(AggregatorV3Node.isValid(_definition(abi.encode(address(aggregator)), 0)));
    }

    function test_IsValid_ReturnsTrueWhenLatestRoundIsInvalid() public {
        aggregator.setRoundData(5, -1, 0, 0, 4);

        assertTrue(AggregatorV3Node.isValid(_definition(abi.encode(address(aggregator)), 0)));
    }

    function test_IsValid_ReturnsTrueForMaxDecimals() public {
        aggregator.setDecimals(type(uint8).max);

        assertTrue(AggregatorV3Node.isValid(_definition(abi.encode(address(aggregator)), 0)));
    }

    function test_IsValid_ReturnsFalseWhenHasParents() public view {
        assertFalse(AggregatorV3Node.isValid(_definition(abi.encode(address(aggregator)), 1)));
    }

    function test_IsValid_ReturnsFalseWhenParamsEmpty() public view {
        assertFalse(AggregatorV3Node.isValid(_definition("", 0)));
    }

    function test_IsValid_ReturnsFalseWhenParamsAbove32Bytes() public view {
        assertFalse(
            AggregatorV3Node.isValid(_definition(abi.encodePacked(abi.encode(address(aggregator)), uint8(0)), 0))
        );
    }

    function test_IsValid_ReturnsTrueForMaxAddress() public {
        address maxAddress = address(type(uint160).max);
        vm.etch(maxAddress, address(aggregator).code);

        assertTrue(AggregatorV3Node.isValid(_definition(abi.encode(maxAddress), 0)));
    }

    function test_IsValid_Revert_AddressAboveMax() public {
        vm.expectRevert();
        this.isValid(_definition(abi.encode(uint256(type(uint160).max) + 1), 0));
    }

    function test_IsValid_Revert_AggregatorHasNoCode() public {
        vm.expectRevert();
        this.isValid(_definition(abi.encode(makeAddr("eoa")), 0));
    }

    function test_IsValid_Revert_LatestRoundDataReverts() public {
        aggregator.setShouldRevertOnLatestRoundData(true);

        vm.expectRevert(MockAggregatorV3.LatestRoundDataReverted.selector);
        this.isValid(_definition(abi.encode(address(aggregator)), 0));
    }

    function test_IsValid_Revert_DecimalsReverts() public {
        aggregator.setShouldRevertOnDecimals(true);

        vm.expectRevert(MockAggregatorV3.DecimalsReverted.selector);
        this.isValid(_definition(abi.encode(address(aggregator)), 0));
    }

    function test_IsValid_Revert_LatestRoundDataReturnDataBelow160Bytes() public {
        vm.mockCall(address(aggregator), abi.encodeCall(IAggregatorV3.latestRoundData, ()), new bytes(159));

        vm.expectRevert();
        this.isValid(_definition(abi.encode(address(aggregator)), 0));
    }

    function test_IsValid_Revert_RoundIdAboveUint80() public {
        vm.mockCall(
            address(aggregator),
            abi.encodeCall(IAggregatorV3.latestRoundData, ()),
            abi.encode(uint256(type(uint80).max) + 1, 2000e8, UPDATED_AT, UPDATED_AT, 1)
        );

        vm.expectRevert();
        this.isValid(_definition(abi.encode(address(aggregator)), 0));
    }

    function test_IsValid_Revert_DecimalsReturnDataBelow32Bytes() public {
        vm.mockCall(address(aggregator), abi.encodeCall(IAggregatorV3.decimals, ()), new bytes(31));

        vm.expectRevert();
        this.isValid(_definition(abi.encode(address(aggregator)), 0));
    }

    function test_IsValid_Revert_DecimalsAboveUint8() public {
        vm.mockCall(address(aggregator), abi.encodeCall(IAggregatorV3.decimals, ()), abi.encode(uint256(256)));

        vm.expectRevert();
        this.isValid(_definition(abi.encode(address(aggregator)), 0));
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function process(bytes memory parameters) external view returns (NodeOutput.Data memory) {
        return AggregatorV3Node.process(parameters);
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function isValid(NodeDefinition.Data memory nodeDefinition) external view returns (bool) {
        return AggregatorV3Node.isValid(nodeDefinition);
    }

    function _definition(bytes memory parameters, uint256 parentCount)
        internal
        pure
        returns (NodeDefinition.Data memory)
    {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.AGGREGATOR_V3, parameters: parameters, parents: new bytes32[](parentCount)
        });
    }
}
