// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {BorrowablePool} from "../../pool/BorrowablePool.sol";
import {CloneFactory} from "../abstract/CloneFactory.sol";

/// @title  BorrowablePoolFactory
/// @notice Specific Factory that clones and initializes `BorrowablePool`.
/// @dev    Every clone is initialized with `FEE_REGISTRY` rather than a fee registry taken from the encoded data, so a
///         pool deployed through this factory always reads its Onlend fee configuration from it.
contract BorrowablePoolFactory is CloneFactory {
    /// @notice Fee registry every clone is initialized with.
    address public immutable FEE_REGISTRY;

    /// @param implementation `BorrowablePool` Implementation every clone delegatecalls to
    /// @param feeRegistry    Fee registry every clone is initialized with
    constructor(address implementation, address feeRegistry) CloneFactory(implementation) {
        FEE_REGISTRY = feeRegistry;
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "BorrowablePool1.0.0Factory";
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
            address operatorFeeConfigurator,
            address initialHookReceiver,
            uint256 initialBeforeHookBitmap,
            uint256 initialAfterHookBitmap,
            address lendingCore,
            bool initialFlashLoansEnabled,
            IERC20Metadata asset,
            string memory name,
            string memory symbol,
            address debtToken,
            address operatorFeeRecipient
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
                bool,
                IERC20Metadata,
                string,
                string,
                address,
                address
            )
        );

        BorrowablePool(instance)
            .initialize(
                defaultAdmin,
                hookUpdater,
                flashLoanConfigurator,
                operatorFeeConfigurator,
                initialHookReceiver,
                initialBeforeHookBitmap,
                initialAfterHookBitmap,
                lendingCore,
                initialFlashLoansEnabled,
                asset,
                name,
                symbol,
                debtToken,
                FEE_REGISTRY,
                operatorFeeRecipient
            );
    }
}
