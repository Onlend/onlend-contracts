// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CloneFactory} from "../abstract/CloneFactory.sol";
import {IVersioned} from "../../interfaces/IVersioned.sol";
import {TargetHealthLiquidationEngine} from "../../liquidation/TargetHealthLiquidationEngine.sol";

/// @title  TargetHealthLiquidationEngineFactory
/// @notice Specific Factory that clones and initializes `TargetHealthLiquidationEngine`.
contract TargetHealthLiquidationEngineFactory is CloneFactory {
    /// @param implementation `TargetHealthLiquidationEngine` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "TargetHealthLiquidationEngine1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (
            address defaultAdmin,
            address oracleUpdater,
            address liquidationConfigurator,
            address oracle,
            uint256 targetHealthFactor,
            uint256 bonusRampStartHealth,
            uint256 bonusRampEndHealth,
            uint256 minLeftoverValue,
            uint256 closeOutThreshold,
            TargetHealthLiquidationEngine.CollateralBonusConfig[] memory collateralBonusConfigs
        ) = abi.decode(
            data,
            (
                address,
                address,
                address,
                address,
                uint256,
                uint256,
                uint256,
                uint256,
                uint256,
                TargetHealthLiquidationEngine.CollateralBonusConfig[]
            )
        );

        TargetHealthLiquidationEngine(instance)
            .initialize(
                defaultAdmin,
                oracleUpdater,
                liquidationConfigurator,
                oracle,
                targetHealthFactor,
                bonusRampStartHealth,
                bonusRampEndHealth,
                minLeftoverValue,
                closeOutThreshold,
                collateralBonusConfigs
            );
    }
}
