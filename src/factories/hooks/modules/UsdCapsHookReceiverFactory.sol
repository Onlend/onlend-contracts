// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../../abstract/CloneFactory.sol";
import {UsdCapsHookReceiver} from "../../../hooks/modules/UsdCapsHookReceiver.sol";
import {CapsHookReceiver} from "../../../hooks/modules/abstract/CapsHookReceiver.sol";
import {IVersioned} from "../../../interfaces/IVersioned.sol";

/// @title  UsdCapsHookReceiverFactory
/// @notice Specific Factory that clones and initializes `UsdCapsHookReceiver`.
contract UsdCapsHookReceiverFactory is CloneFactory {
    /// @param implementation `UsdCapsHookReceiver` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "UsdCapsHookReceiver1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (
            address defaultAdmin,
            address capsConfigurator,
            address oracleUpdater,
            address oracle,
            CapsHookReceiver.PoolCapConfig[] memory initialCaps
        ) = abi.decode(data, (address, address, address, address, CapsHookReceiver.PoolCapConfig[]));

        UsdCapsHookReceiver(instance).initialize(defaultAdmin, capsConfigurator, oracleUpdater, oracle, initialCaps);
    }
}
