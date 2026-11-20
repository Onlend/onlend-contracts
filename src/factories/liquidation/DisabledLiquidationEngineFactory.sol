// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../abstract/CloneFactory.sol";
import {IVersioned} from "../../interfaces/IVersioned.sol";
import {DisabledLiquidationEngine} from "../../liquidation/DisabledLiquidationEngine.sol";

/// @title  DisabledLiquidationEngineFactory
/// @notice Specific Factory that clones and initializes `DisabledLiquidationEngine`.
contract DisabledLiquidationEngineFactory is CloneFactory {
    /// @notice Thrown when initialization data is provided for a stateless liquidation engine.
    error UnexpectedInitializationData();

    /// @param implementation `DisabledLiquidationEngine` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "DisabledLiquidationEngine1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    /// @dev `data` must be empty because `DisabledLiquidationEngine` has no configuration.
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        if (data.length != 0) revert UnexpectedInitializationData();

        DisabledLiquidationEngine(instance).initialize();
    }
}
