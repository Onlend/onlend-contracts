// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IVersioned} from "../interfaces/IVersioned.sol";
import {BasePool} from "./abstract/BasePool.sol";
import {Collateralisable} from "./abstract/Collateralisable.sol";

/// @title CollateralisablePool
/// @notice Protected collateral pool controlled by LendingCore.
/// @dev Holds collateral 1:1 in the underlying asset. Protected deposits are not borrowable and do not accrue
///      pool-level interest. They can still be flash loaned while flash loans are enabled.
///      Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract CollateralisablePool is Collateralisable {
    IERC20Metadata private _asset;

    /// @notice Emitted once when the pool is initialised, naming the contracts it is bound to.
    /// @param lendingCore LendingCore allowed to execute pool operations.
    /// @param asset Underlying asset the pool holds as collateral.
    /// @param collateralToken Token tracking collateral positions.
    event PoolInitialised(address indexed lendingCore, address indexed asset, address collateralToken);

    /// @notice Locks the Implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a collateralisable pool clone with its collateral token.
    /// @dev Callable once per clone.
    /// @param defaultAdmin Initial default admin role member.
    /// @param hookUpdater Initial hook updater role member.
    /// @param flashLoanConfigurator Initial flash loan config role member.
    /// @param initialHookReceiver Initial hook receiver, or the zero address to disable hooks.
    /// @param initialBeforeHookBitmap Initial before-hook bitmap.
    /// @param initialAfterHookBitmap Initial after-hook bitmap.
    /// @param lendingCore_ LendingCore address authorized to execute pool operations.
    /// @param initialFlashLoansEnabled Whether flash loans start enabled.
    /// @param asset_ Underlying asset held by the pool.
    /// @param collateralToken_ Collateral token associated with this pool.
    function initialize(
        address defaultAdmin,
        address hookUpdater,
        address flashLoanConfigurator,
        address initialHookReceiver,
        uint256 initialBeforeHookBitmap,
        uint256 initialAfterHookBitmap,
        address lendingCore_,
        bool initialFlashLoansEnabled,
        IERC20Metadata asset_,
        address collateralToken_
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

        _asset = asset_;

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);

        emit PoolInitialised(lendingCore_, address(asset_), collateralToken_);
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "CollateralisablePool";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc BasePool
    function asset() public view override(BasePool) returns (address) {
        return address(_asset);
    }

    /// @inheritdoc BasePool
    /// @dev All assets accounted for by a collateralisable pool are collateral, so this equals `totalCollateral()`.
    function totalAssets() public view override(BasePool) returns (uint256) {
        return totalCollateral();
    }

    /// @notice Applies protected collateral deposit accounting.
    /// @dev Protected pools only support underlying-denominated collateral requests: `assets` must be non-zero and
    ///      `shares` must be zero.
    /// @param caller Account providing the collateral assets.
    /// @param assets Collateral amount denominated in underlying units.
    /// @param shares Must be zero for protected pools.
    /// @param receiver Account whose loan is credited with the collateral.
    /// @return Underlying deposited and a zero share amount, the pool having no shares to derive.
    function _depositCollateral(address caller, uint256 assets, uint256 shares, address receiver)
        internal
        override(BasePool)
        returns (uint256, uint256)
    {
        /// @dev There are no share tokens, so only `assets` amounts are supported and `shares` must be zero.
        if (assets == 0 || shares != 0) revert InvalidCollateralArgs();

        // LendingCore binds `caller` to the account providing the collateral assets.
        // slither-disable-next-line arbitrary-send-erc20
        SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
        _collateralToken.mint(receiver, assets);

        return (assets, 0);
    }

    /// @notice Applies protected collateral withdrawal accounting.
    /// @dev Protected pools only support underlying-denominated collateral requests: `assets` must be non-zero and
    ///      `shares` must be zero.
    /// @param caller Account whose collateral position is debited.
    /// @param assets Collateral amount denominated in underlying units.
    /// @param shares Must be zero for protected pools.
    /// @param receiver Account that receives the withdrawn underlying.
    /// @return Underlying withdrawn and a zero share amount, the pool having no shares to derive.
    function _withdrawCollateral(address caller, uint256 assets, uint256 shares, address receiver)
        internal
        override(BasePool)
        returns (uint256, uint256)
    {
        /// @dev There are no share tokens, so only `assets` amounts are supported and `shares` must be zero.
        if (assets == 0 || shares != 0) revert InvalidCollateralArgs();

        _collateralToken.burn(caller, assets);
        SafeERC20.safeTransfer(_asset, receiver, assets);

        return (assets, 0);
    }

    /// @notice Applies protected collateral seizure accounting.
    /// @dev Identical to a withdrawal: protected assets are never lent to borrowers, so outside a flash loan's callback
    ///      the pool always holds the underlying a collateral position is worth and a seizure cannot be short of
    ///      liquidity to settle in.
    /// @param violator Account whose collateral position is debited.
    /// @param assets Collateral amount to seize, denominated in underlying units.
    /// @param receiver Account that receives the seized underlying.
    /// @return Underlying seized and a zero share amount, the seizure being settled in underlying.
    function _seizeCollateral(address violator, uint256 assets, address receiver)
        internal
        override(BasePool)
        returns (uint256, uint256)
    {
        return _withdrawCollateral(violator, assets, 0, receiver);
    }
}
