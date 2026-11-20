// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../../abstract/CloneFactory.sol";
import {NominalCapsHookReceiver} from "../../../hooks/modules/NominalCapsHookReceiver.sol";
import {CapsHookReceiver} from "../../../hooks/modules/abstract/CapsHookReceiver.sol";
import {IVersioned} from "../../../interfaces/IVersioned.sol";

/// @title  NominalCapsHookReceiverFactory
/// @notice Specific Factory that clones and initializes `NominalCapsHookReceiver`.
contract NominalCapsHookReceiverFactory is CloneFactory {
    /// @param implementation `NominalCapsHookReceiver` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "NominalCapsHookReceiver1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (address defaultAdmin, address capsConfigurator, CapsHookReceiver.PoolCapConfig[] memory initialCaps) =
            abi.decode(data, (address, address, CapsHookReceiver.PoolCapConfig[]));

        NominalCapsHookReceiver(instance).initialize(defaultAdmin, capsConfigurator, initialCaps);
    }
}
