// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {CollateralisablePool} from "../../pool/CollateralisablePool.sol";
import {CloneFactory} from "../abstract/CloneFactory.sol";

/// @title  CollateralisablePoolFactory
/// @notice Specific Factory that clones and initializes `CollateralisablePool`.
contract CollateralisablePoolFactory is CloneFactory {
    /// @param implementation `CollateralisablePool` Implementation every clone delegatecalls to
    constructor(address implementation) CloneFactory(implementation) {}

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "CollateralisablePool1.0.0Factory";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CloneFactory
    function _initialize(address instance, bytes calldata data) internal override(CloneFactory) {
        (
            address defaultAdmin,
            address hookUpdater,
            address flashLoanConfigurator,
            address initialHookReceiver,
            uint256 initialBeforeHookBitmap,
            uint256 initialAfterHookBitmap,
            address lendingCore,
            bool initialFlashLoansEnabled,
            IERC20Metadata asset,
            address collateralToken
        ) = abi.decode(
            data, (address, address, address, address, uint256, uint256, address, bool, IERC20Metadata, address)
        );

        CollateralisablePool(instance)
            .initialize(
                defaultAdmin,
                hookUpdater,
                flashLoanConfigurator,
                initialHookReceiver,
                initialBeforeHookBitmap,
                initialAfterHookBitmap,
                lendingCore,
                initialFlashLoansEnabled,
                asset,
                collateralToken
            );
    }
}
