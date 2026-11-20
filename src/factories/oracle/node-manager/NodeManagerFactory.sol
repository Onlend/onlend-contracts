// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../../abstract/CloneFactory.sol";
import {IVersioned} from "../../../interfaces/IVersioned.sol";
import {NodeManager} from "../../../oracle/node-manager/NodeManager.sol";
import {NodeDefinition} from "../../../oracle/node-manager/lib/NodeDefinition.sol";

/// @title  NodeManagerFactory
/// @notice Specific Factory that clones and initializes `NodeManager`.
contract NodeManagerFactory is CloneFactory {
    /// @param implementation `NodeManager` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "NodeManager1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        NodeDefinition.Data[] memory nodes = abi.decode(data, (NodeDefinition.Data[]));

        NodeManager(instance).initialize(nodes);
    }
}
