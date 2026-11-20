// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {NodeDefinition} from "../NodeDefinition.sol";
import {NodeOutput} from "../NodeOutput.sol";
import {MathUtils} from "../../../../lib/MathUtils.sol";

/// @title  PriceDeviationCircuitBreakerNode
/// @notice Guards a parent node against deviating from a comparison parent, optionally falling back to a third parent.
library PriceDeviationCircuitBreakerNode {
    /// @notice Thrown when the primary price deviates beyond the tolerance and no fallback parent is configured.
    /// @param  deviation  Deviation of the comparison price from the primary price, in 18 decimal places
    error DeviationToleranceExceeded(uint256 deviation);

    /// @notice Thrown when the primary price is zero and no fallback parent is configured.
    /// @param  nodeType  Type of the node that produced the primary output
    error ZeroPrice(NodeDefinition.NodeType nodeType);

    /// @notice Processes a PRICE_DEVIATION_CIRCUIT_BREAKER node and returns its output.
    /// @dev    The deviation is `|primary - comparison| / primary`, rounded up so a deviation just above the tolerance
    ///         is never accepted. Returns the primary parent when it is non-zero and the deviation does not exceed the
    ///         tolerance, otherwise the fallback parent (without checking it) if configured, otherwise reverts.
    /// @param  parentNodeOutputs  Primary and comparison parent outputs, optionally followed by the fallback output
    /// @param  parameters         ABI-encoded uint256 deviation tolerance in 18 decimal places (1e18 = 100%)
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        internal
        pure
        returns (NodeOutput.Data memory)
    {
        uint256 deviationTolerance = abi.decode(parameters, (uint256));
        uint256 price = parentNodeOutputs[0].price;

        if (price == 0) {
            if (parentNodeOutputs.length == 3) return parentNodeOutputs[2];
            revert ZeroPrice(parentNodeOutputs[0].nodeType);
        }

        uint256 comparisonPrice = parentNodeOutputs[1].price;
        uint256 difference = price > comparisonPrice ? price - comparisonPrice : comparisonPrice - price;
        uint256 deviation = Math.mulDiv(difference, MathUtils.ONE_18_DP, price, Math.Rounding.Ceil);

        if (deviation <= deviationTolerance) return parentNodeOutputs[0];
        if (parentNodeOutputs.length == 3) return parentNodeOutputs[2];
        revert DeviationToleranceExceeded(deviation);
    }

    /// @notice Returns true when the node definition is valid for a PRICE_DEVIATION_CIRCUIT_BREAKER node.
    /// @param  nodeDefinition  Node definition to validate
    function isValid(NodeDefinition.Data memory nodeDefinition) internal pure returns (bool) {
        return nodeDefinition.parents.length > 1 && nodeDefinition.parents.length < 4
            && nodeDefinition.parameters.length == 32;
    }
}
