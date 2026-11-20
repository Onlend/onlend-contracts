// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../../../../abstract/CloneFactory.sol";
import {Whitelistable} from "../../../../../whitelist/abstract/Whitelistable.sol";
import {IVersioned} from "../../../../../interfaces/IVersioned.sol";
import {WhitelistCondition} from "../../../../../pool/irm/modules/condition/WhitelistCondition.sol";

/// @title  WhitelistConditionFactory
/// @notice Specific Factory that clones and initializes `WhitelistCondition`.
contract WhitelistConditionFactory is CloneFactory {
    /// @param implementation `WhitelistCondition` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "WhitelistCondition1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (address defaultAdmin, address whitelistConfigurator, Whitelistable.WhitelistUpdate[] memory updates) =
            abi.decode(data, (address, address, Whitelistable.WhitelistUpdate[]));

        WhitelistCondition(instance).initialize(defaultAdmin, whitelistConfigurator, updates);
    }
}
