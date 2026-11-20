// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../../abstract/CloneFactory.sol";
import {WhitelistHookReceiver} from "../../../hooks/modules/WhitelistHookReceiver.sol";
import {IVersioned} from "../../../interfaces/IVersioned.sol";
import {Whitelistable} from "../../../whitelist/abstract/Whitelistable.sol";

/// @title  WhitelistHookReceiverFactory
/// @notice Specific Factory that clones and initializes `WhitelistHookReceiver`.
contract WhitelistHookReceiverFactory is CloneFactory {
    /// @param implementation `WhitelistHookReceiver` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "WhitelistHookReceiver1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (address defaultAdmin, address whitelistConfigurator, Whitelistable.WhitelistUpdate[] memory updates) =
            abi.decode(data, (address, address, Whitelistable.WhitelistUpdate[]));

        WhitelistHookReceiver(instance).initialize(defaultAdmin, whitelistConfigurator, updates);
    }
}
