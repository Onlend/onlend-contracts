// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IVersioned} from "../../../interfaces/IVersioned.sol";
import {ComposedIRM} from "../../../pool/irm/ComposedIRM.sol";
import {CloneFactory} from "../../abstract/CloneFactory.sol";

/// @title  ComposedIRMFactory
/// @notice Specific Factory that clones and initializes `ComposedIRM`.
contract ComposedIRMFactory is CloneFactory {
    /// @param implementation `ComposedIRM` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "ComposedIRM1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (
            address borrowRateCaller,
            ComposedIRM.BorrowRateType borrowRateType,
            bytes memory borrowRateParams,
            ComposedIRM.RetentionRateType retentionRateType,
            bytes memory retentionRateParams,
            ComposedIRM.ConditionType conditionType,
            bytes memory conditionParams,
            address defaultAdmin,
            address borrowRateUpdater,
            address retentionRateUpdater,
            address conditionUpdater
        ) = abi.decode(
            data,
            (
                address,
                ComposedIRM.BorrowRateType,
                bytes,
                ComposedIRM.RetentionRateType,
                bytes,
                ComposedIRM.ConditionType,
                bytes,
                address,
                address,
                address,
                address
            )
        );

        ComposedIRM(instance)
            .initialize(
                borrowRateCaller,
                borrowRateType,
                borrowRateParams,
                retentionRateType,
                retentionRateParams,
                conditionType,
                conditionParams,
                defaultAdmin,
                borrowRateUpdater,
                retentionRateUpdater,
                conditionUpdater
            );
    }
}
