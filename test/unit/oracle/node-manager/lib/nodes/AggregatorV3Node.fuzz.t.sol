// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {AggregatorV3Node} from "src/oracle/node-manager/lib/nodes/AggregatorV3Node.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {MockAggregatorV3} from "../../../../../mocks/MockAggregatorV3.sol";

contract AggregatorV3NodeFuzzTest is Test {
    /// @dev Highest answer that fits `int256`.
    uint256 internal constant MAX_ANSWER = uint256(type(int256).max);
    /// @dev Highest whole-unit price whose 18-decimal output fits `uint256`. One whole unit fits `int256` up to 76
    ///      feed decimals.
    uint256 internal constant MAX_UNITS = type(uint256).max / 1e18;
    uint256 internal constant UPDATED_AT = 1;

    MockAggregatorV3 internal aggregator;

    function setUp() public {
        aggregator = new MockAggregatorV3(8, 2000e8, UPDATED_AT);
    }

    // process()

    function testFuzz_Process_ReturnsAnswerUnchangedAtEighteenDecimals(uint256 answer) public {
        answer = bound(answer, 0, MAX_ANSWER);
        aggregator.setDecimals(18);
        aggregator.setAnswer(SafeCast.toInt256(answer), UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, answer);
    }

    function testFuzz_Process_PreservesWholeUnitsAtAnyDecimals(uint256 units, uint8 feedDecimals) public {
        feedDecimals = uint8(bound(feedDecimals, 0, 76));
        units = bound(units, 0, Math.min(MAX_UNITS, MAX_ANSWER / 10 ** feedDecimals));
        aggregator.setDecimals(feedDecimals);
        aggregator.setAnswer(SafeCast.toInt256(units * 10 ** feedDecimals), UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, units * 1e18);
    }

    function testFuzz_Process_IsStrictlyIncreasingBelowEighteenDecimals(
        uint256 lower,
        uint256 higher,
        uint8 feedDecimals
    ) public {
        lower = bound(lower, 0, MAX_UNITS - 1);
        higher = bound(higher, lower + 1, MAX_UNITS);
        feedDecimals = uint8(bound(feedDecimals, 0, 17));
        aggregator.setDecimals(feedDecimals);
        aggregator.setAnswer(SafeCast.toInt256(lower), UPDATED_AT);
        uint256 lowerPrice = AggregatorV3Node.process(abi.encode(address(aggregator))).price;
        aggregator.setAnswer(SafeCast.toInt256(higher), UPDATED_AT);

        uint256 higherPrice = AggregatorV3Node.process(abi.encode(address(aggregator))).price;

        assertGt(higherPrice, lowerPrice);
    }

    function testFuzz_Process_IgnoresSubUnitRemainderAboveEighteenDecimals(
        uint256 price,
        uint256 remainder,
        uint8 feedDecimals
    ) public {
        feedDecimals = uint8(bound(feedDecimals, 19, 95));
        uint256 unit = 10 ** (feedDecimals - 18);
        price = bound(price, 0, MAX_ANSWER / unit);
        remainder = bound(remainder, 0, Math.min(unit - 1, MAX_ANSWER - price * unit));
        aggregator.setDecimals(feedDecimals);
        aggregator.setAnswer(SafeCast.toInt256(price * unit + remainder), UPDATED_AT);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.price, price);
    }

    function testFuzz_Process_ReturnsUpdatedAt(uint256 now_, uint256 updatedAt) public {
        now_ = bound(now_, 0, type(uint64).max);
        updatedAt = bound(updatedAt, 1, type(uint256).max);
        vm.warp(now_);
        aggregator.setAnswer(2000e8, updatedAt);

        NodeOutput.Data memory output = AggregatorV3Node.process(abi.encode(address(aggregator)));

        assertEq(output.timestamp, updatedAt);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.AGGREGATOR_V3));
    }

    function testFuzz_Process_RevertsWhenAnswerNegative(int256 answer) public {
        answer = bound(answer, type(int256).min, -1);
        aggregator.setAnswer(answer, UPDATED_AT);

        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedIntToUint.selector, answer));
        this.process(abi.encode(address(aggregator)));
    }

    function testFuzz_Process_RevertsWhenUpdatedAtZero(int256 answer) public {
        answer = bound(answer, 0, type(int256).max);
        aggregator.setAnswer(answer, 0);

        vm.expectRevert(abi.encodeWithSelector(AggregatorV3Node.ZeroUpdatedAt.selector, address(aggregator)));
        this.process(abi.encode(address(aggregator)));
    }

    function testFuzz_Process_RevertsWhenScalingFactorOverflows(uint8 feedDecimals) public {
        feedDecimals = uint8(bound(feedDecimals, 96, type(uint8).max));
        aggregator.setDecimals(feedDecimals);

        vm.expectRevert(stdError.arithmeticError);
        this.process(abi.encode(address(aggregator)));
    }

    // isValid()

    function testFuzz_IsValid_ReturnsTrueForAnyDecimalsAndRound(uint8 feedDecimals, int256 answer, uint256 updatedAt)
        public
    {
        aggregator.setDecimals(feedDecimals);
        aggregator.setAnswer(answer, updatedAt);

        assertTrue(AggregatorV3Node.isValid(_definition(abi.encode(address(aggregator)), 0)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenHasParents(uint256 parentCount) public view {
        parentCount = bound(parentCount, 1, 16);

        assertFalse(AggregatorV3Node.isValid(_definition(abi.encode(address(aggregator)), parentCount)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenParamsLengthNot32(uint256 length) public view {
        length = bound(length, 0, 255);
        if (length >= 32) ++length;

        assertFalse(AggregatorV3Node.isValid(_definition(new bytes(length), 0)));
    }

    function testFuzz_IsValid_RevertsWhenAddressAboveMax(uint256 raw) public {
        raw = bound(raw, uint256(type(uint160).max) + 1, type(uint256).max);

        vm.expectRevert();
        this.isValid(_definition(abi.encode(raw), 0));
    }

    function testFuzz_IsValid_RevertsWhenAggregatorHasNoCode(uint256 privateKey) public {
        privateKey = bound(privateKey, 1, SECP256K1_ORDER - 1);

        vm.expectRevert();
        this.isValid(_definition(abi.encode(vm.addr(privateKey)), 0));
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
