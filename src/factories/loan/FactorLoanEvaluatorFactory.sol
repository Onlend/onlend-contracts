// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../abstract/CloneFactory.sol";
import {IVersioned} from "../../interfaces/IVersioned.sol";
import {FactorLoanEvaluator} from "../../loan/FactorLoanEvaluator.sol";

/// @title  FactorLoanEvaluatorFactory
/// @notice Specific Factory that clones and initializes `FactorLoanEvaluator`.
contract FactorLoanEvaluatorFactory is CloneFactory {
    /// @param implementation `FactorLoanEvaluator` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "FactorLoanEvaluator1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (
            address defaultAdmin,
            address oracleUpdater,
            address factorConfigurator,
            address oracle,
            uint256 minHealthFactor,
            FactorLoanEvaluator.PoolFactorConfig[] memory poolFactorConfigs
        ) = abi.decode(data, (address, address, address, address, uint256, FactorLoanEvaluator.PoolFactorConfig[]));

        FactorLoanEvaluator(instance)
            .initialize(defaultAdmin, oracleUpdater, factorConfigurator, oracle, minHealthFactor, poolFactorConfigs);
    }
}
