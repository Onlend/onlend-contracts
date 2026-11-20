// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IVersioned} from "../interfaces/IVersioned.sol";
import {FactoryRegistry} from "./abstract/FactoryRegistry.sol";
import {ILendingAppFactory} from "./interfaces/ILendingAppFactory.sol";

/// @title  LendingAppFactory
/// @notice Single entry point for deploying a whole lending app instance. See {ILendingAppFactory}.
contract LendingAppFactory is ILendingAppFactory, FactoryRegistry {
    /// @param  owner_ Initial owner, authorised to register/remove Clone Factories
    constructor(address owner_) FactoryRegistry(owner_) {}

    /// @inheritdoc ILendingAppFactory
    function deploy(ModuleConfig[] calldata modules)
        external
        override(ILendingAppFactory)
        returns (DeployedModule[] memory deployed)
    {
        deployed = new DeployedModule[](modules.length);
        for (uint256 i = 0; i < modules.length; i++) {
            address cloneFactory = modules[i].cloneFactory;

            address instance = _clone(cloneFactory, modules[i].salt, modules[i].data);
            deployed[i] = DeployedModule({cloneFactory: cloneFactory, instance: instance});

            emit ModuleDeployed(msg.sender, cloneFactory, instance);
        }
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "LendingAppFactory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }
}
