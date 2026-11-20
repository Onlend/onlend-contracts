// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../../abstract/CloneFactory.sol";
import {PauseHookReceiver} from "../../../hooks/modules/PauseHookReceiver.sol";
import {IVersioned} from "../../../interfaces/IVersioned.sol";

/// @title  PauseHookReceiverFactory
/// @notice Specific Factory that clones and initialises `PauseHookReceiver`.
contract PauseHookReceiverFactory is CloneFactory {
    /// @param implementation `PauseHookReceiver` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "PauseHookReceiver1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (address defaultAdmin, address[] memory pauseConfigurators, address unpauseConfigurator) =
            abi.decode(data, (address, address[], address));

        PauseHookReceiver(instance).initialize(defaultAdmin, pauseConfigurators, unpauseConfigurator);
    }
}
