// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IVersioned} from "../../interfaces/IVersioned.sol";

/// @title  ILendingAppFactory
/// @notice Whole-app orchestrator: batches many Clone Factory deploys into a single call.
interface ILendingAppFactory is IVersioned {
    /// @notice One module to deploy: which Clone Factory to route through, and its init args.
    /// @param  cloneFactory Registered Clone Factory address to deploy through
    /// @param  salt Caller-chosen salt
    /// @param  data ABI-encoded initialization fields for the new instance
    struct ModuleConfig {
        address cloneFactory;
        bytes32 salt;
        bytes data;
    }

    /// @notice One module deployed by `deploy`.
    /// @param  cloneFactory Clone Factory the module was deployed through
    /// @param  instance Address of the deployed instance
    struct DeployedModule {
        address cloneFactory;
        address instance;
    }

    /// @notice Emitted when a module is deployed by `deploy`.
    /// @param  deployer Account that called `deploy`, to which the module's salt is bound
    /// @param  cloneFactory Clone Factory the module was deployed through
    /// @param  instance Address of the deployed instance
    event ModuleDeployed(address indexed deployer, address indexed cloneFactory, address indexed instance);

    /// @notice Deploys every module in `modules`, in order, through its named Clone Factory.
    /// @dev    Reverts the entire call if any entry's Clone Factory is not registered.
    /// @param  modules Modules to deploy, in order
    /// @return deployed Deployed modules, in the same order as `modules`
    function deploy(ModuleConfig[] calldata modules) external returns (DeployedModule[] memory deployed);
}
