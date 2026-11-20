// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../abstract/CloneFactory.sol";
import {IVersioned} from "../../interfaces/IVersioned.sol";
import {NoCollateralLoanEvaluator} from "../../loan/NoCollateralLoanEvaluator.sol";

/// @title  NoCollateralLoanEvaluatorFactory
/// @notice Specific Factory that clones and initializes `NoCollateralLoanEvaluator`.
contract NoCollateralLoanEvaluatorFactory is CloneFactory {
    /// @notice Thrown when initialization data is provided for a stateless loan evaluator.
    error UnexpectedInitializationData();

    /// @param implementation `NoCollateralLoanEvaluator` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "NoCollateralLoanEvaluator1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    /// @dev `data` must be empty because `NoCollateralLoanEvaluator` has no configuration.
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        if (data.length != 0) revert UnexpectedInitializationData();

        NoCollateralLoanEvaluator(instance).initialize();
    }
}
