// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {PriceDeviationCircuitBreakerNode} from "src/oracle/node-manager/lib/nodes/PriceDeviationCircuitBreakerNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";

contract PriceDeviationCircuitBreakerNodeTest is Test {
    uint256 internal constant PRICE = 100e18;
    uint256 internal constant ONE_PERCENT = 0.01e18;
    uint256 internal constant FALLBACK_PRICE = 7e18;

    // process()

    function test_Process_ReturnsPrimaryWhenPricesEqual() public pure {
        NodeOutput.Data memory output = _process(PRICE, PRICE, ONE_PERCENT, true);

        _assertPrimary(output);
    }

    function test_Process_ReturnsPrimaryWhenComparisonAboveAtTolerance() public pure {
        NodeOutput.Data memory output = _process(PRICE, 101e18, ONE_PERCENT, true);

        _assertPrimary(output);
    }

    function test_Process_ReturnsPrimaryWhenComparisonBelowAtTolerance() public pure {
        NodeOutput.Data memory output = _process(PRICE, 99e18, ONE_PERCENT, true);

        _assertPrimary(output);
    }

    function test_Process_ReturnsFallbackWhenOneWeiAboveTolerance() public pure {
        NodeOutput.Data memory output = _process(PRICE, 101e18 + 1, ONE_PERCENT, true);

        _assertFallback(output);
    }

    function test_Process_ReturnsFallbackWhenOneWeiBelowTolerance() public pure {
        NodeOutput.Data memory output = _process(PRICE, 99e18 - 1, ONE_PERCENT, true);

        _assertFallback(output);
    }

    function test_Process_ReturnsPrimaryWhenComparisonZeroAndToleranceIsHundredPercent() public pure {
        NodeOutput.Data memory output = _process(PRICE, 0, 1e18, false);

        _assertPrimary(output);
    }

    function test_Process_RoundsDeviationUp() public pure {
        // 1/3 = 0.333...3 when rounded down, which would equal the tolerance and pass.
        NodeOutput.Data memory output = _process(3, 4, 0.333333333333333333e18, true);

        _assertFallback(output);
    }

    function test_Process_Revert_DeviationExceededWithoutFallback() public {
        NodeOutput.Data[] memory parents = _parents(PRICE, 102e18, false);

        vm.expectRevert(
            abi.encodeWithSelector(PriceDeviationCircuitBreakerNode.DeviationToleranceExceeded.selector, 0.02e18)
        );
        this.process(parents, abi.encode(ONE_PERCENT));
    }

    function test_Process_Revert_DeviationExceededReportsRoundedUpDeviation() public {
        NodeOutput.Data[] memory parents = _parents(3, 4, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                PriceDeviationCircuitBreakerNode.DeviationToleranceExceeded.selector, 0.333333333333333334e18
            )
        );
        this.process(parents, abi.encode(0.333333333333333333e18));
    }

    function test_Process_ReturnsFallbackWhenPrimaryIsZero() public pure {
        NodeOutput.Data memory output = _process(0, 0, ONE_PERCENT, true);

        _assertFallback(output);
    }

    function test_Process_Revert_ZeroPriceWithoutFallback() public {
        NodeOutput.Data[] memory parents = _parents(0, 0, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                PriceDeviationCircuitBreakerNode.ZeroPrice.selector, NodeDefinition.NodeType.CONSTANT
            )
        );
        this.process(parents, abi.encode(ONE_PERCENT));
    }

    function test_Process_Revert_DeviationOverflows() public {
        NodeOutput.Data[] memory parents = _parents(1, type(uint256).max, true);

        vm.expectRevert(stdError.arithmeticError);
        this.process(parents, abi.encode(ONE_PERCENT));
    }

    // isValid()

    function test_IsValid_ReturnsTrueForTwoParents() public pure {
        assertTrue(PriceDeviationCircuitBreakerNode.isValid(_definition(abi.encode(ONE_PERCENT), 2)));
    }

    function test_IsValid_ReturnsTrueForThreeParents() public pure {
        assertTrue(PriceDeviationCircuitBreakerNode.isValid(_definition(abi.encode(ONE_PERCENT), 3)));
    }

    function test_IsValid_ReturnsFalseWhenOneParent() public pure {
        assertFalse(PriceDeviationCircuitBreakerNode.isValid(_definition(abi.encode(ONE_PERCENT), 1)));
    }

    function test_IsValid_ReturnsFalseWhenFourParents() public pure {
        assertFalse(PriceDeviationCircuitBreakerNode.isValid(_definition(abi.encode(ONE_PERCENT), 4)));
    }

    function test_IsValid_ReturnsFalseWhenParamsEmpty() public pure {
        assertFalse(PriceDeviationCircuitBreakerNode.isValid(_definition("", 2)));
    }

    function test_IsValid_ReturnsFalseWhenParamsAbove32Bytes() public pure {
        assertFalse(PriceDeviationCircuitBreakerNode.isValid(_definition(abi.encodePacked(ONE_PERCENT, uint8(0)), 2)));
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        external
        pure
        returns (NodeOutput.Data memory)
    {
        return PriceDeviationCircuitBreakerNode.process(parentNodeOutputs, parameters);
    }

    function _process(uint256 price, uint256 comparisonPrice, uint256 tolerance, bool withFallback)
        internal
        pure
        returns (NodeOutput.Data memory)
    {
        return PriceDeviationCircuitBreakerNode.process(
            _parents(price, comparisonPrice, withFallback), abi.encode(tolerance)
        );
    }

    function _assertPrimary(NodeOutput.Data memory output) internal pure {
        assertEq(output.price, PRICE);
        assertEq(output.timestamp, 1);
    }

    function _assertFallback(NodeOutput.Data memory output) internal pure {
        assertEq(output.price, FALLBACK_PRICE);
        assertEq(output.timestamp, 3);
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
