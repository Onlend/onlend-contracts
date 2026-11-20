// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {Phase} from "../../hooks/interfaces/IHookReceiver.sol";
import {Hookable} from "../../hooks/abstract/Hookable.sol";
import {ActionLib} from "../../hooks/lib/ActionLib.sol";

import {IPool} from "../interfaces/IPool.sol";
import {FlashLendable} from "./FlashLendable.sol";

/// @title BasePool
/// @notice Base contract defining the pool operations which are routed through LendingCore.
/// @dev Provides the LendingCore-gated entry points and the hooks fired around them, and implements the whole of
///      `IPool` so every pool answers the same ABI whatever it can actually do. An operation a pool does not support
///      reverts `FunctionNotAvailable` from its internal function, and the total behind it reads zero. A pool gains an
///      operation by inheriting the contract that implements that capability. Every pool offers flash loans of its
///      asset, which are called directly rather than through LendingCore.
abstract contract BasePool is IPool, FlashLendable, Hookable {
    /// @notice LendingCore contract allowed to execute pool operations.
    address private _lendingCore;

    /// @notice Thrown when calling a LendingCore-only function from an account other than `lendingCore`.
    error NotLendingCoreCaller();

    /// @notice Reverts when a pool is asked to execute an operation it does not support.
    error FunctionNotAvailable();

    /// @notice Reverts when a token the pool denominates against reports different decimals than the pool expects.
    /// @param token Token reporting the mismatched decimals.
    /// @param decimals Decimals the token reports.
    /// @param expected Decimals the pool requires.
    error InvalidTokenDecimals(address token, uint8 decimals, uint8 expected);

    /// @notice Restricts a function to `lendingCore`.
    modifier onlyLendingCore() {
        if (msg.sender != _lendingCore) revert NotLendingCoreCaller();
        _;
    }

    /// @notice Initializes role members, the LendingCore dependency and flash loan status for an inheriting pool.
    /// @dev Must be called from the concrete pool's initializer, which is also responsible for initializing access
    ///      control and granting `DEFAULT_ADMIN_ROLE`.
    /// @param hookUpdater Initial hook updater role member.
    /// @param flashLoanConfigurator Initial flash loan config role member.
    /// @param initialHookReceiver Initial hook receiver, or the zero address to disable hooks.
    /// @param initialBeforeHookBitmap Initial before-hook bitmap.
    /// @param initialAfterHookBitmap Initial after-hook bitmap.
    /// @param lendingCore_ LendingCore address authorized to execute pool operations.
    /// @param initialFlashLoansEnabled Whether flash loans start enabled.
    function _initializePool(
        address hookUpdater,
        address flashLoanConfigurator,
        address initialHookReceiver,
        uint256 initialBeforeHookBitmap,
        uint256 initialAfterHookBitmap,
        address lendingCore_,
        bool initialFlashLoansEnabled
    ) internal onlyInitializing {
        _initializeHookable(hookUpdater, initialHookReceiver, initialBeforeHookBitmap, initialAfterHookBitmap);
        _initializeFlashLendable(flashLoanConfigurator, initialFlashLoansEnabled);
        _lendingCore = lendingCore_;
    }

    /// @inheritdoc IPool
    /// @dev The BEFORE hook carries the request as asked for; the AFTER hook carries the amounts the pool resolved it
    ///      to, so a receiver acting on a share-denominated deposit sees the underlying it moved.
    function depositCollateral(address caller, uint256 assets, uint256 shares, address receiver)
        external
        override(IPool)
        onlyLendingCore
        returns (uint256 assetsDeposited, uint256 sharesMinted)
    {
        _fireHook(Phase.BEFORE, ActionLib.POOL_DEPOSIT_COLLATERAL, abi.encode(receiver, caller, assets, shares));

        (assetsDeposited, sharesMinted) = _depositCollateral(caller, assets, shares, receiver);

        _fireHook(
            Phase.AFTER, ActionLib.POOL_DEPOSIT_COLLATERAL, abi.encode(receiver, caller, assetsDeposited, sharesMinted)
        );
    }

    /// @inheritdoc IPool
    /// @dev The BEFORE hook carries the request as asked for; the AFTER hook carries the amounts the pool resolved it
    ///      to, so a receiver acting on a share-denominated withdrawal sees the underlying it moved.
    function withdrawCollateral(address caller, uint256 assets, uint256 shares, address receiver)
        external
        override(IPool)
        onlyLendingCore
        returns (uint256 assetsWithdrawn, uint256 sharesBurned)
    {
        _fireHook(Phase.BEFORE, ActionLib.POOL_WITHDRAW_COLLATERAL, abi.encode(caller, receiver, assets, shares));

        (assetsWithdrawn, sharesBurned) = _withdrawCollateral(caller, assets, shares, receiver);

        _fireHook(
            Phase.AFTER, ActionLib.POOL_WITHDRAW_COLLATERAL, abi.encode(caller, receiver, assetsWithdrawn, sharesBurned)
        );
    }

    /// @inheritdoc IPool
    /// @dev The AFTER hook carries the shares the seizure moved alongside the underlying it was priced at, since what
    ///      `receiver` is paid in depends on the pool.
    function seizeCollateral(address violator, uint256 assets, address receiver)
        external
        override(IPool)
        onlyLendingCore
        returns (uint256 assetsSeized, uint256 sharesSeized)
    {
        _fireHook(Phase.BEFORE, ActionLib.POOL_SEIZE_COLLATERAL, abi.encode(violator, receiver, assets));

        (assetsSeized, sharesSeized) = _seizeCollateral(violator, assets, receiver);

        _fireHook(
            Phase.AFTER, ActionLib.POOL_SEIZE_COLLATERAL, abi.encode(violator, receiver, assetsSeized, sharesSeized)
        );
    }

    /// @inheritdoc IPool
    function borrow(address caller, uint256 amount, address receiver) external override(IPool) onlyLendingCore {
        _fireHook(Phase.BEFORE, ActionLib.POOL_BORROW, abi.encode(caller, receiver, amount));

        _borrow(caller, amount, receiver);

        _fireHook(Phase.AFTER, ActionLib.POOL_BORROW, abi.encode(caller, receiver, amount));
    }

    /// @inheritdoc IPool
    function repay(address caller, uint256 amount, address receiver)
        external
        override(IPool)
        onlyLendingCore
        returns (uint256 repayment)
    {
        _fireHook(Phase.BEFORE, ActionLib.POOL_REPAY, abi.encode(receiver, caller, amount));

        repayment = _repay(caller, amount, receiver);

        _fireHook(Phase.AFTER, ActionLib.POOL_REPAY, abi.encode(receiver, caller, repayment));
    }

    /// @inheritdoc IPool
    function writeOffDebt(address account) external override(IPool) onlyLendingCore returns (uint256 writtenOff) {
        _fireHook(Phase.BEFORE, ActionLib.POOL_WRITE_OFF_DEBT, abi.encode(account));

        writtenOff = _writeOffDebt(account);

        _fireHook(Phase.AFTER, ActionLib.POOL_WRITE_OFF_DEBT, abi.encode(account, writtenOff));
    }

    /// @inheritdoc FlashLendable
    /// @dev Lends the pool's asset without touching its accounting, so the receiver may put the loan through any pool
    ///      operation within the callback, such as depositing it as collateral. The pool's balance falls short of what
    ///      it has accounted for until the loan is repaid, so an operation within the callback that pays underlying out
    ///      can fail on the transfer rather than on the pool's own checks. Fires `POOL_FLASH_LOAN` hooks around it.
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        public
        override(FlashLendable)
        returns (bool success)
    {
        _fireHook(Phase.BEFORE, ActionLib.POOL_FLASH_LOAN, abi.encode(msg.sender, address(receiver), amount));

        success = super.flashLoan(receiver, token, amount, data);

        _fireHook(Phase.AFTER, ActionLib.POOL_FLASH_LOAN, abi.encode(msg.sender, address(receiver), amount));
    }

    /// @inheritdoc IPool
    function lendingCore() public view override(IPool) returns (address) {
        return _lendingCore;
    }

    /// @inheritdoc IPool
    function asset() public view virtual override(IPool) returns (address);

    /// @inheritdoc IPool
    function totalAssets() public view virtual override(IPool) returns (uint256);

    /// @inheritdoc IPool
    /// @dev Zero unless the pool supports collateral.
    function totalCollateral() public view virtual override(IPool) returns (uint256) {
        return 0;
    }

    /// @inheritdoc IPool
    /// @dev Zero unless the pool supports borrowing.
    function totalDebt() public view virtual override(IPool) returns (uint256) {
        return 0;
    }

    /// @inheritdoc IPool
    /// @dev Zero unless the pool supports collateral.
    function collateralOf(address) public view virtual override(IPool) returns (uint256) {
        return 0;
    }

    /// @inheritdoc IPool
    /// @dev Zero unless the pool supports borrowing.
    function debtOf(address) public view virtual override(IPool) returns (uint256) {
        return 0;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, AccessControlEnumerableUpgradeable, FlashLendable)
        returns (bool)
    {
        return interfaceId == type(IPool).interfaceId || interfaceId == type(IVersioned).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @notice Applies collateral deposit accounting.
    /// @dev Reverts unless the pool supports collateral. Returns the request with the derived amount filled in.
    function _depositCollateral(address, uint256, uint256, address) internal virtual returns (uint256, uint256) {
        revert FunctionNotAvailable();
    }

    /// @notice Applies collateral withdrawal accounting.
    /// @dev Reverts unless the pool supports collateral. Returns the request with the derived amount filled in.
    function _withdrawCollateral(address, uint256, uint256, address) internal virtual returns (uint256, uint256) {
        revert FunctionNotAvailable();
    }

    /// @notice Applies collateral seizure accounting.
    /// @dev Reverts unless the pool supports collateral. Returns the underlying seized and the shares it moved.
    function _seizeCollateral(address, uint256, address) internal virtual returns (uint256, uint256) {
        revert FunctionNotAvailable();
    }

    /// @notice Applies debt accounting and transfers borrowed underlying to a receiver.
    /// @dev Reverts unless the pool supports borrowing.
    function _borrow(address, uint256, address) internal virtual {
        revert FunctionNotAvailable();
    }

    /// @notice Applies repayment accounting for an account's debt.
    /// @dev Reverts unless the pool supports borrowing.
    function _repay(address, uint256, address) internal virtual returns (uint256) {
        revert FunctionNotAvailable();
    }

    /// @notice Applies write-off accounting for an account's debt.
    /// @dev Reverts unless the pool supports borrowing.
    function _writeOffDebt(address) internal virtual returns (uint256) {
        revert FunctionNotAvailable();
    }

    /// @inheritdoc FlashLendable
    /// @dev The pool's asset.
    function _flashLoanToken() internal view override(FlashLendable) returns (address) {
        return asset();
    }

    /// @notice Validates that a token the pool denominates against reports the decimals the pool expects.
    /// @dev Deployment wires each token its own decimals, so a pool asserts the parity its accounting assumes rather
    ///      than trusting it.
    /// @param token Token to validate.
    /// @param expected Decimals the pool requires the token to report.
    function _validateTokenDecimals(address token, uint8 expected) internal view {
        uint8 actual = IERC20Metadata(token).decimals();
        if (actual != expected) revert InvalidTokenDecimals(token, actual, expected);
    }
}
