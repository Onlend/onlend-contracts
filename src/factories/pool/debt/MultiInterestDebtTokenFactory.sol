// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IVersioned} from "../../../interfaces/IVersioned.sol";
import {MultiInterestDebtToken} from "../../../pool/debt/MultiInterestDebtToken.sol";
import {CloneFactory} from "../../abstract/CloneFactory.sol";

/// @title  MultiInterestDebtTokenFactory
/// @notice Specific Factory that clones and initializes `MultiInterestDebtToken`.
contract MultiInterestDebtTokenFactory is CloneFactory {
    /// @param implementation `MultiInterestDebtToken` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "MultiInterestDebtToken1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (
            address pool,
            string memory name,
            string memory symbol,
            uint8 decimals,
            address defaultAdmin,
            address irmUpdater,
            address[] memory irmIds
        ) = abi.decode(data, (address, string, string, uint8, address, address, address[]));

        MultiInterestDebtToken(instance).initialize(pool, name, symbol, decimals, defaultAdmin, irmUpdater, irmIds);
    }
}
