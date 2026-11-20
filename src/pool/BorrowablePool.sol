// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IVersioned} from "../interfaces/IVersioned.sol";
import {Borrowable} from "./abstract/Borrowable.sol";

/// @title  BorrowablePool
/// @notice ERC-4626 pool whose deposited assets can be borrowed through LendingCore.
/// @dev    Supply and borrow only: the pool issues no collateral positions, so the collateral operations revert
///         `FunctionNotAvailable` and `totalCollateral()` reads zero. Depositors hold ordinary ERC-4626 shares, which
///         cannot back a loan on this pool.
///         Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract BorrowablePool is Borrowable {
    /// @notice Emitted once when the pool is initialised, naming the contracts it is bound to.
    /// @param lendingCore LendingCore allowed to execute pool operations.
    /// @param asset Underlying asset the pool lends.
    /// @param debtToken Token tracking debt positions.
    event PoolInitialised(address indexed lendingCore, address indexed asset, address debtToken);

    /// @notice Locks the Implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a borrowable pool clone with its debt token.
    /// @dev Callable once per clone.
    /// @param  defaultAdmin            Initial default admin role member.
    /// @param  hookUpdater              Initial hook updater role member.
    /// @param  flashLoanConfigurator    Initial flash loan config role member.
    /// @param  operatorFeeConfigurator  Initial operator fee config role member.
    /// @param  initialHookReceiver      Initial hook receiver, or the zero address to disable hooks.
    /// @param  initialBeforeHookBitmap  Initial before-hook bitmap.
    /// @param  initialAfterHookBitmap   Initial after-hook bitmap.
    /// @param  lendingCore_             LendingCore address authorized to execute pool operations.
    /// @param  initialFlashLoansEnabled Whether flash loans start enabled.
    /// @param  asset_                   Underlying asset managed by the ERC-4626 vault.
    /// @param  name_                    Pool share token name.
    /// @param  symbol_                  Pool share token symbol.
    /// @param  debtToken_               Debt token associated with this pool.
    /// @param  feeRegistry_             Registry the Onlend fee configuration and fee recipient are read from.
    /// @param  operatorFeeRecipient_    Initial account the operator's fee shares are minted to.
    function initialize(
        address defaultAdmin,
        address hookUpdater,
        address flashLoanConfigurator,
        address operatorFeeConfigurator,
        address initialHookReceiver,
        uint256 initialBeforeHookBitmap,
        uint256 initialAfterHookBitmap,
        address lendingCore_,
        bool initialFlashLoansEnabled,
        IERC20Metadata asset_,
        string calldata name_,
        string calldata symbol_,
        address debtToken_,
        address feeRegistry_,
        address operatorFeeRecipient_
    ) external initializer {
        __AccessControlEnumerable_init();
        _initializePool(
            hookUpdater,
            flashLoanConfigurator,
            initialHookReceiver,
            initialBeforeHookBitmap,
            initialAfterHookBitmap,
            lendingCore_,
            initialFlashLoansEnabled
        );
        _initializeBorrowable(
            operatorFeeConfigurator, asset_, name_, symbol_, debtToken_, feeRegistry_, operatorFeeRecipient_
        );

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);

        emit PoolInitialised(lendingCore_, address(asset_), debtToken_);
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "BorrowablePool";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }
}
