// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {LendingCore} from "../../lending-core/LendingCore.sol";
import {CloneFactory} from "../abstract/CloneFactory.sol";

/// @title  LendingCoreFactory
/// @notice Specific Factory that clones and initializes `LendingCore`.
contract LendingCoreFactory is CloneFactory {
    /// @param implementation `LendingCore` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "LendingCore1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (
            address loanEvaluator,
            address liquidationEngine,
            address defaultAdmin,
            address hookUpdater,
            address initialHookReceiver,
            uint256 initialBeforeHookBitmap,
            uint256 initialAfterHookBitmap,
            address poolLister,
            address loanUpdater,
            address liquidationUpdater,
            address badDebtConfigurator,
            address metadataConfigurator,
            bool initialSocialiseBadDebt,
            string memory jsonPayload,
            address[] memory initialPools
        ) = abi.decode(
            data,
            (
                address,
                address,
                address,
                address,
                address,
                uint256,
                uint256,
                address,
                address,
                address,
                address,
                address,
                bool,
                string,
                address[]
            )
        );

        LendingCore(instance)
            .initialize(
                loanEvaluator,
                liquidationEngine,
                defaultAdmin,
                hookUpdater,
                initialHookReceiver,
                initialBeforeHookBitmap,
                initialAfterHookBitmap,
                poolLister,
                loanUpdater,
                liquidationUpdater,
                badDebtConfigurator,
                metadataConfigurator,
                initialSocialiseBadDebt,
                jsonPayload,
                initialPools
            );
    }
}
