// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../abstract/CloneFactory.sol";
import {IVersioned} from "../../interfaces/IVersioned.sol";
import {NodeOracle} from "../../oracle/NodeOracle.sol";

/// @title  NodeOracleFactory
/// @notice Specific Factory that clones and initializes `NodeOracle`.
contract NodeOracleFactory is CloneFactory {
    /// @param implementation `NodeOracle` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "NodeOracle1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (address defaultAdmin, address nodeUpdater, address nodeManager, NodeOracle.PoolNodeConfig[] memory poolNodes) =
            abi.decode(data, (address, address, address, NodeOracle.PoolNodeConfig[]));

        NodeOracle(instance).initialize(defaultAdmin, nodeUpdater, nodeManager, poolNodes);
    }
}
