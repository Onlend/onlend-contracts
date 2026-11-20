// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../interfaces/IVersioned.sol";
import {UtilsLib} from "../lib/UtilsLib.sol";
import {BasePool} from "./abstract/BasePool.sol";
import {Borrowable} from "./abstract/Borrowable.sol";
import {Collateralisable} from "./abstract/Collateralisable.sol";

/// @title  CollateralisableBorrowablePool
/// @notice ERC-4626 pool whose deposited assets can be borrowed through LendingCore and whose positions can back a
///         loan.
/// @dev    Collateral positions are escrowed as the pool's own ERC-4626 shares: a deposit mints shares to this contract
///         and an equal amount of collateral token to the depositor, so collateral earns the deposit rate like any
///         other share balance. See `Borrowable` for the supply and debt accounting.
///         Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract CollateralisableBorrowablePool is Borrowable, Collateralisable {
    /// @notice Emitted once when the pool is initialised, naming the contracts it is bound to.
    /// @param lendingCore LendingCore allowed to execute pool operations.
    /// @param asset Underlying asset the pool lends and holds as collateral.
    /// @param collateralToken Token tracking collateral positions.
    /// @param debtToken Token tracking debt positions.
    event PoolInitialised(
        address indexed lendingCore, address indexed asset, address collateralToken, address debtToken
    );

    /// @notice Locks the Implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a collateralisable borrowable pool clone with its collateral and debt tokens.
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
    /// @param  collateralToken_         Collateral token associated with this pool.
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
        address collateralToken_,
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
        _initializeCollateralisable(collateralToken_, asset_.decimals());
        _initializeBorrowable(
            operatorFeeConfigurator, asset_, name_, symbol_, debtToken_, feeRegistry_, operatorFeeRecipient_
        );

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);

        emit PoolInitialised(lendingCore_, address(asset_), collateralToken_, debtToken_);
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "CollateralisableBorrowablePool";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc BasePool
    /// @dev Disambiguates `BasePool`'s declaration from the capability that implements it.
    function asset() public view override(BasePool, Borrowable) returns (address) {
        return Borrowable.asset();
    }

    /// @inheritdoc BasePool
    /// @dev Disambiguates `BasePool`'s declaration from the capability that implements it.
    function totalAssets() public view override(BasePool, Borrowable) returns (uint256) {
        return Borrowable.totalAssets();
    }

    /// @inheritdoc BasePool
    /// @dev Disambiguates `BasePool`'s declaration from the capability that implements it.
    function totalCollateral() public view override(BasePool, Collateralisable) returns (uint256) {
        return Collateralisable.totalCollateral();
    }

    /// @inheritdoc BasePool
    /// @dev Disambiguates `BasePool`'s declaration from the capability that implements it.
    function totalDebt() public view override(BasePool, Borrowable) returns (uint256) {
        return Borrowable.totalDebt();
    }

    /// @inheritdoc BasePool
    /// @dev Disambiguates `BasePool`'s declaration from the capability that implements it.
    function collateralOf(address account) public view override(BasePool, Collateralisable) returns (uint256) {
        return Collateralisable.collateralOf(account);
    }

    /// @inheritdoc BasePool
    /// @dev Disambiguates `BasePool`'s declaration from the capability that implements it.
    function debtOf(address account) public view override(BasePool, Borrowable) returns (uint256) {
        return Borrowable.debtOf(account);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Borrowable, Collateralisable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Applies borrowable collateral deposit accounting.
    /// @dev Exactly one of `assets` or `shares` must be non-zero. The other amount is calculated after interest is
    ///      accrued. Pool shares are minted to this contract as escrow and matching collateral tokens are minted to
    ///      `receiver`.
    /// @param  caller   Account providing the underlying assets.
    /// @param  assets   Underlying amount to deposit, or zero when specifying `shares`.
    /// @param  shares   Collateral share amount to mint, or zero when specifying `assets`.
    /// @param  receiver Account receiving the collateral tokens.
    /// @return Underlying deposited and pool shares minted, with the derived one of the two filled in.
    function _depositCollateral(address caller, uint256 assets, uint256 shares, address receiver)
        internal
        override(BasePool)
        returns (uint256, uint256)
    {
        /// @dev Caller must specify exactly one of `assets` or `shares`; the other is derived.
        if (!UtilsLib.exactlyOneZero(assets, shares)) revert InvalidCollateralArgs();

        _accrueInterest();

        if (assets > 0) {
            uint256 maxAssets = maxDeposit(address(this));
            if (assets > maxAssets) revert ERC4626ExceededMaxDeposit(address(this), assets, maxAssets);
            shares = previewDeposit(assets);
        } else {
            uint256 maxShares = maxMint(address(this));
            if (shares > maxShares) revert ERC4626ExceededMaxMint(address(this), shares, maxShares);
            assets = previewMint(shares);
        }

        /// @dev Mint share tokens to itself to act as an escrow, and mint the receiver an equal amount of collateral
        ///      token.
        _deposit(caller, address(this), assets, shares);
        _collateralToken.mint(receiver, shares);

        _updateInterestRates();

        return (assets, shares);
    }

    /// @notice Applies borrowable collateral withdrawal accounting.
    /// @dev Exactly one of `assets` or `shares` must be non-zero. The other amount is calculated after interest is
    ///      accrued. Collateral tokens and the matching escrowed pool shares are burned before transferring the
    ///      underlying to `receiver`.
    /// @param  caller   Account whose collateral tokens are burned.
    /// @param  assets   Underlying amount to withdraw, or zero when specifying `shares`.
    /// @param  shares   Collateral share amount to redeem, or zero when specifying `assets`.
    /// @param  receiver Account receiving the underlying assets.
    /// @return Underlying withdrawn and pool shares burned, with the derived one of the two filled in.
    function _withdrawCollateral(address caller, uint256 assets, uint256 shares, address receiver)
        internal
        override(BasePool)
        returns (uint256, uint256)
    {
        /// @dev Caller must specify exactly one of `assets` or `shares`; the other is derived.
        if (!UtilsLib.exactlyOneZero(assets, shares)) revert InvalidCollateralArgs();

        _accrueInterest();

        if (assets > 0) {
            uint256 maxAssets = maxWithdraw(address(this));
            if (assets > maxAssets) revert ERC4626ExceededMaxWithdraw(address(this), assets, maxAssets);
            shares = previewWithdraw(assets);
        } else {
            uint256 maxShares = maxRedeem(address(this));
            if (shares > maxShares) revert ERC4626ExceededMaxRedeem(address(this), shares, maxShares);
            assets = previewRedeem(shares);
        }

        /// @dev Burn the caller's collateral tokens and the escrowed share tokens, returning the underlying assets to
        ///      the receiver.
        _collateralToken.burn(caller, shares);
        _withdraw(address(this), receiver, address(this), assets, shares);

        _updateInterestRates();

        return (assets, shares);
    }

    /// @notice Applies borrowable collateral seizure accounting.
    /// @dev Hands the escrowed pool shares themselves to `receiver` instead of redeeming them for underlying: the
    ///      seizure moves the position rather than exiting it, so it never draws on idle liquidity. A liquidation is
    ///      therefore not blocked by the pool being lent out. The shares are priced after interest is accrued and
    ///      rounded up.
    /// @param  violator Account whose collateral tokens are burned.
    /// @param  assets   Underlying amount to seize; the escrowed shares it prices to are transferred.
    /// @param  receiver Account receiving the escrowed pool shares.
    /// @return Underlying the seizure was priced at and the escrowed pool shares handed to `receiver`.
    function _seizeCollateral(address violator, uint256 assets, address receiver)
        internal
        override(BasePool)
        returns (uint256, uint256)
    {
        /// @dev Seizures are underlying-denominated, so an amount is always required.
        if (assets == 0) revert InvalidCollateralArgs();

        _accrueInterest();

        uint256 shares = previewWithdraw(assets);

        /// @dev Burn the violator's collateral tokens and transfer the escrowed share tokens to the receiver.
        _collateralToken.burn(violator, shares);
        ERC20Upgradeable._transfer(address(this), receiver, shares);

        _updateInterestRates();

        return (assets, shares);
    }

    /// @inheritdoc BasePool
    /// @dev Disambiguates `BasePool`'s declaration from the capability that implements it.
    function _borrow(address caller, uint256 amount, address receiver) internal override(BasePool, Borrowable) {
        Borrowable._borrow(caller, amount, receiver);
    }

    /// @inheritdoc BasePool
    /// @dev Disambiguates `BasePool`'s declaration from the capability that implements it.
    function _repay(address caller, uint256 amount, address receiver)
        internal
        override(BasePool, Borrowable)
        returns (uint256)
    {
        return Borrowable._repay(caller, amount, receiver);
    }

    /// @inheritdoc BasePool
    /// @dev Disambiguates `BasePool`'s declaration from the capability that implements it.
    function _writeOffDebt(address account) internal override(BasePool, Borrowable) returns (uint256) {
        return Borrowable._writeOffDebt(account);
    }
}
