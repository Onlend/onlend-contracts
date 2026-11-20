// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../abstract/CloneFactory.sol";
import {MultiHookReceiver} from "../../hooks/MultiHookReceiver.sol";
import {IVersioned} from "../../interfaces/IVersioned.sol";

/// @title  MultiHookReceiverFactory
/// @notice Specific Factory that clones and initializes `MultiHookReceiver`.
contract MultiHookReceiverFactory is CloneFactory {
    /// @param implementation `MultiHookReceiver` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "MultiHookReceiver1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (
            address defaultAdmin,
            address hookReceiversUpdater,
            address[] memory hookCallers,
            MultiHookReceiver.HookReceiverConfig[] memory configs
        ) = abi.decode(data, (address, address, address[], MultiHookReceiver.HookReceiverConfig[]));

        MultiHookReceiver(instance).initialize(defaultAdmin, hookReceiversUpdater, hookCallers, configs);
    }
}
