// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";

import {PriceDeviationCircuitBreakerNode} from "src/oracle/node-manager/lib/nodes/PriceDeviationCircuitBreakerNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

contract PriceDeviationCircuitBreakerNodeFuzzTest is Test {
    uint256 internal constant MAX_PRICE = 1e36;
    uint256 internal constant FALLBACK_PRICE = 7e18;

    // process()

    function testFuzz_Process_ReturnsPrimaryWhenWithinTolerance(
        uint256 price,
        uint256 tolerance,
        uint256 difference,
        bool comparisonAbove
    ) public pure {
        price = bound(price, 1, MAX_PRICE);
        tolerance = bound(tolerance, 0, 1e18);
        difference = bound(difference, 0, _maxDifferenceWithinTolerance(price, tolerance));
        uint256 comparisonPrice = comparisonAbove ? price + difference : price - difference;

        NodeOutput.Data memory output =
            PriceDeviationCircuitBreakerNode.process(_parents(price, comparisonPrice, true), abi.encode(tolerance));

        assertEq(output.price, price);
        assertEq(output.timestamp, 1);
    }

    function testFuzz_Process_ReturnsFallbackWhenBeyondTolerance(uint256 price, uint256 tolerance, uint256 difference)
        public
        pure
    {
        price = bound(price, 1, MAX_PRICE);
        tolerance = bound(tolerance, 0, 1e18);
        difference = bound(difference, _maxDifferenceWithinTolerance(price, tolerance) + 1, 2 * MAX_PRICE);

        NodeOutput.Data memory output =
            PriceDeviationCircuitBreakerNode.process(_parents(price, price + difference, true), abi.encode(tolerance));

        assertEq(output.price, FALLBACK_PRICE);
        assertEq(output.timestamp, 3);
    }

    function testFuzz_Process_RevertsWhenBeyondToleranceWithoutFallback(
        uint256 price,
        uint256 tolerance,
        uint256 difference
    ) public {
        price = bound(price, 1, MAX_PRICE);
        tolerance = bound(tolerance, 0, 1e18);
        difference = bound(difference, _maxDifferenceWithinTolerance(price, tolerance) + 1, 2 * MAX_PRICE);
        NodeOutput.Data[] memory parents = _parents(price, price + difference, false);

        vm.expectPartialRevert(PriceDeviationCircuitBreakerNode.DeviationToleranceExceeded.selector);
        this.process(parents, abi.encode(tolerance));
    }

    function testFuzz_Process_ReturnsFallbackWhenPrimaryIsZero(uint256 comparisonPrice, uint256 tolerance) public pure {
        NodeOutput.Data memory output =
            PriceDeviationCircuitBreakerNode.process(_parents(0, comparisonPrice, true), abi.encode(tolerance));

        assertEq(output.price, FALLBACK_PRICE);
        assertEq(output.timestamp, 3);
    }

    // isValid()

    function testFuzz_IsValid_ReturnsTrueWhenValidParams(uint256 tolerance, uint256 parentCount) public pure {
        parentCount = bound(parentCount, 2, 3);

        assertTrue(PriceDeviationCircuitBreakerNode.isValid(_definition(abi.encode(tolerance), parentCount)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenTooFewParents(uint256 tolerance, uint256 parentCount) public pure {
        parentCount = bound(parentCount, 0, 1);

        assertFalse(PriceDeviationCircuitBreakerNode.isValid(_definition(abi.encode(tolerance), parentCount)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenTooManyParents(uint256 tolerance, uint256 parentCount) public pure {
        parentCount = bound(parentCount, 4, 16);

        assertFalse(PriceDeviationCircuitBreakerNode.isValid(_definition(abi.encode(tolerance), parentCount)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenParamsLengthNot32(bytes calldata parameters) public pure {
        vm.assume(parameters.length != 32);

        assertFalse(PriceDeviationCircuitBreakerNode.isValid(_definition(parameters, 2)));
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        external
        pure
        returns (NodeOutput.Data memory)
    {
        return PriceDeviationCircuitBreakerNode.process(parentNodeOutputs, parameters);
    }

    /// @dev Largest difference whose relative deviation stays within the tolerance: `difference * 1e18 <=
    ///      tolerance * price` holds exactly when `difference <= floor(tolerance * price / 1e18)`.
    function _maxDifferenceWithinTolerance(uint256 price, uint256 tolerance) internal pure returns (uint256) {
        return Math.mulDiv(tolerance, price, 1e18);
    }

    function _parents(uint256 price, uint256 comparisonPrice, bool withFallback)
        internal
        pure
        returns (NodeOutput.Data[] memory parents)
    {
        parents = new NodeOutput.Data[](withFallback ? 3 : 2);
        parents[0] = NodeOutput.Data(price, 1, NodeDefinition.NodeType.CONSTANT, 0, 0);
        parents[1] = NodeOutput.Data(comparisonPrice, 2, NodeDefinition.NodeType.CONSTANT, 0, 0);
        if (withFallback) parents[2] = NodeOutput.Data(FALLBACK_PRICE, 3, NodeDefinition.NodeType.CONSTANT, 0, 0);
    }

    function _definition(bytes memory parameters, uint256 parentCount)
        internal
        pure
        returns (NodeDefinition.Data memory)
    {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.PRICE_DEVIATION_CIRCUIT_BREAKER,
            parameters: parameters,
            parents: new bytes32[](parentCount)
        });
    }
}
