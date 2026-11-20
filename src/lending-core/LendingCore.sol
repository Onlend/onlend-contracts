// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {Authorisable} from "../authorisation/abstract/Authorisable.sol";
import {IVersioned} from "../interfaces/IVersioned.sol";
import {Phase} from "../hooks/interfaces/IHookReceiver.sol";
import {Hookable} from "../hooks/abstract/Hookable.sol";
import {ActionLib} from "../hooks/lib/ActionLib.sol";
import {LoanPositionLib} from "../lib/LoanPositionLib.sol";
import {ILiquidationEngine} from "../liquidation/interfaces/ILiquidationEngine.sol";
import {ILoanEvaluator} from "../loan/interfaces/ILoanEvaluator.sol";
import {IPool} from "../pool/interfaces/IPool.sol";
import {ILendingCore} from "./interfaces/ILendingCore.sol";

/// @title LendingCore
/// @notice Manages the pool listing and routes user actions to the listed pools. See {ILendingCore}.
/// @dev Enforces loan health through the configured loan evaluator and delegates liquidation math to the configured
///      liquidation engine. Fires before/after hooks around each user action.
///
///      Checks loan health only after `withdrawCollateral` and `borrow`, so it assumes a loan evaluator under which
///      depositing collateral or repaying debt never lowers a loan's health. It is also why `depositCollateral` and
///      `repay` need no authorisation from `onBehalfOf`.
///
///      User actions are non-reentrant, since `borrow` and `withdrawCollateral` pay out before checking loan health.
///      The guard uses transient storage, so LendingCore only works on networks where EIP-1153 is available.
///
///      Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract LendingCore is ILendingCore, Hookable, Authorisable, ReentrancyGuardTransient {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using LoanPositionLib for LoanPosition[];

    /// @notice Lifecycle status of a listed pool.
    /// @dev ACTIVE pools accept new positions; DEPRECATED pools remain listed but are wound down.
    enum PoolStatus {
        NONE,
        ACTIVE,
        DEPRECATED
    }

    /// @notice A listed pool paired with its status.
    /// @param pool The pool address.
    /// @param status The pool's `PoolStatus`.
    struct PoolInfo {
        address pool;
        PoolStatus status;
    }

    /// @notice Role allowed to add new pools and deprecate existing pools.
    bytes32 public constant POOL_LISTING_ROLE = keccak256("POOL_LISTING_ROLE");
    /// @notice Role allowed to set the loan evaluator.
    bytes32 public constant LOAN_UPDATER_ROLE = keccak256("LOAN_UPDATER_ROLE");
    /// @notice Role allowed to set the liquidation engine.
    bytes32 public constant LIQUIDATION_UPDATER_ROLE = keccak256("LIQUIDATION_UPDATER_ROLE");
    /// @notice Role allowed to enable or disable bad debt socialisation.
    bytes32 public constant BAD_DEBT_CONFIG_ROLE = keccak256("BAD_DEBT_CONFIG_ROLE");
    /// @notice Role allowed to set lending app metadata.
    bytes32 public constant METADATA_CONFIG_ROLE = keccak256("METADATA_CONFIG_ROLE");

    /// @dev Evaluator used to assess loan health and liquidatability.
    ILoanEvaluator private _loanEvaluator;
    /// @dev Engine used to compute the collateral to seize and borrows to repay during liquidation.
    ILiquidationEngine private _liquidationEngine;
    /// @dev Whether a liquidation that leaves the violator with debt but no collateral writes that debt off.
    bool private _socialiseBadDebt;

    /// @dev Listed pools keyed by address, each mapped to its `PoolStatus`. Deprecated pools remain in the map so the
    ///      listing stays enumerable.
    EnumerableMap.AddressToUintMap private _pools;

    /// @notice Emitted when the loan evaluator is updated.
    /// @param oldLoanEvaluator Previous loan evaluator address.
    /// @param newLoanEvaluator New loan evaluator address.
    event LoanEvaluatorSet(address indexed oldLoanEvaluator, address indexed newLoanEvaluator);
    /// @notice Emitted when the liquidation engine is updated.
    /// @param oldLiquidationEngine Previous liquidation engine address.
    /// @param newLiquidationEngine New liquidation engine address.
    event LiquidationEngineSet(address indexed oldLiquidationEngine, address indexed newLiquidationEngine);
    /// @notice Emitted when bad debt socialisation is enabled or disabled.
    /// @param enabled Whether bad debt socialisation is now enabled.
    event BadDebtSocialisationSet(bool enabled);
    /// @notice Emitted when the lending app metadata is set.
    /// @param jsonPayload New JSON metadata payload.
    event MetadataSet(string jsonPayload);
    /// @notice Emitted when a pool is added to the listing.
    /// @param pool Added pool address.
    event PoolAdded(address indexed pool);
    /// @notice Emitted when a pool's deprecation status changes.
    /// @param pool Affected pool address.
    /// @param deprecated New deprecation status; true if deprecated, false if reactivated.
    event PoolDeprecationSet(address indexed pool, bool deprecated);
    /// @notice Emitted when collateral is deposited into a pool.
    /// @param pool Pool the collateral was deposited into.
    /// @param onBehalfOf Account whose loan was credited with the collateral.
    /// @param caller Account that provided the underlying.
    /// @param assets Underlying amount deposited.
    /// @param shares Pool shares the deposit minted, or zero for a pool without shares.
    event CollateralDeposited(
        IPool indexed pool, address indexed onBehalfOf, address indexed caller, uint256 assets, uint256 shares
    );
    /// @notice Emitted when collateral is withdrawn from a pool.
    /// @param pool Pool the collateral was withdrawn from.
    /// @param onBehalfOf Account whose loan was debited.
    /// @param caller Account that executed the withdrawal, either `onBehalfOf` or an account it authorised.
    /// @param receiver Account that received the underlying.
    /// @param assets Underlying amount withdrawn.
    /// @param shares Pool shares the withdrawal burned, or zero for a pool without shares.
    event CollateralWithdrawn(
        IPool indexed pool, address indexed onBehalfOf, address caller, address receiver, uint256 assets, uint256 shares
    );
    /// @notice Emitted when underlying is borrowed from a pool.
    /// @param pool Pool borrowed from.
    /// @param onBehalfOf Account whose loan was assigned the debt.
    /// @param caller Account that executed the borrow, either `onBehalfOf` or an account it authorised.
    /// @param receiver Account that received the underlying.
    /// @param amount Underlying amount borrowed.
    event Borrowed(IPool indexed pool, address indexed onBehalfOf, address caller, address receiver, uint256 amount);
    /// @notice Emitted when debt is repaid in a pool outside a liquidation.
    /// @param pool Pool the debt was repaid in.
    /// @param onBehalfOf Account whose debt was reduced.
    /// @param caller Account that provided the underlying.
    /// @param amount Underlying amount repaid.
    event Repaid(IPool indexed pool, address indexed onBehalfOf, address indexed caller, uint256 amount);
    /// @notice Emitted when a violator's debt is repaid in a pool during a liquidation.
    /// @param pool Pool the debt was repaid in.
    /// @param violator Account whose debt was reduced.
    /// @param liquidator Account that provided the underlying.
    /// @param amount Underlying amount repaid.
    event LiquidationRepaid(IPool indexed pool, address indexed violator, address indexed liquidator, uint256 amount);
    /// @notice Emitted when collateral is seized from a violator during a liquidation.
    /// @param pool Pool the collateral was seized from.
    /// @param violator Account whose collateral was seized.
    /// @param liquidator Account that received the seized collateral.
    /// @param assets Underlying amount seized.
    /// @param shares Pool shares the seizure moved to `liquidator`, or zero for a pool without shares.
    event CollateralSeized(
        IPool indexed pool, address indexed violator, address indexed liquidator, uint256 assets, uint256 shares
    );
    /// @notice Emitted when a violator's remaining debt in a pool is written off during a liquidation that left its
    ///         loan with no collateral.
    /// @param pool Pool the debt was written off in.
    /// @param violator Account whose debt was written off.
    /// @param liquidator Account whose liquidation left the loan with no collateral.
    /// @param amount Underlying amount of debt written off.
    event BadDebtSocialised(IPool indexed pool, address indexed violator, address indexed liquidator, uint256 amount);
    /// @notice Emitted once a loan is liquidated, after its borrows are repaid, its collateral is seized and any bad
    ///         debt is written off.
    /// @param violator Account whose loan was liquidated.
    /// @param liquidator Account that repaid the borrows and received the seized collateral.
    /// @param health Health of the loan before the liquidation, as reported by the loan evaluator.
    event Liquidated(address indexed violator, address indexed liquidator, uint256 health);

    /// @notice Reverts when a loan evaluator does not support `ILoanEvaluator`.
    /// @param loanEvaluator Invalid loan evaluator address.
    error InvalidLoanEvaluator(address loanEvaluator);
    /// @notice Reverts when a liquidation engine does not support `ILiquidationEngine`.
    /// @param liquidationEngine Invalid liquidation engine address.
    error InvalidLiquidationEngine(address liquidationEngine);
    /// @notice Reverts when setting bad debt socialisation to the status it already has.
    /// @param enabled The unchanged bad debt socialisation status.
    error SocialiseBadDebtUnchanged(bool enabled);
    /// @notice Reverts when a pool does not support `IPool`.
    /// @param pool Invalid pool address.
    error InvalidPool(address pool);
    /// @notice Reverts when adding a pool that is already listed.
    /// @param pool Already-listed pool address.
    error PoolAlreadyAdded(address pool);
    /// @notice Reverts when operating on a pool that is not listed.
    /// @param pool Unlisted pool address.
    error PoolNotListed(address pool);
    /// @notice Reverts when setting a pool's deprecation status to the status it already has.
    /// @param pool Affected pool address.
    /// @param deprecated The unchanged deprecation status.
    error PoolDeprecatedUnchanged(address pool, bool deprecated);
    /// @notice Reverts when operating on a deprecated pool.
    /// @param pool Deprecated pool address.
    error PoolDeprecated(address pool);
    /// @notice Reverts when an action would leave the account's loan unhealthy.
    /// @param account The account whose loan would become unhealthy.
    error LoanUnhealthy(address account);
    /// @notice Reverts when attempting to liquidate a loan that is not liquidatable.
    /// @param account The account whose loan is not liquidatable.
    error LoanNotLiquidatable(address account);

    /// @notice Locks the Implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a LendingCore clone.
    /// @dev Callable once per clone.
    /// @param loanEvaluator_ Initial loan evaluator; must support `ILoanEvaluator`.
    /// @param liquidationEngine_ Initial liquidation engine; must support `ILiquidationEngine`.
    /// @param defaultAdmin Initial default admin role member.
    /// @param hookUpdater Initial hook updater role member.
    /// @param initialHookReceiver Initial hook receiver, or the zero address to disable hooks.
    /// @param initialBeforeHookBitmap Initial before-hook bitmap.
    /// @param initialAfterHookBitmap Initial after-hook bitmap.
    /// @param poolLister Initial pool listing role member.
    /// @param loanUpdater Initial loan updater role member.
    /// @param liquidationUpdater Initial liquidation updater role member.
    /// @param badDebtConfigurator Initial bad debt configurator role member.
    /// @param metadataConfigurator Initial metadata configurator role member.
    /// @param initialSocialiseBadDebt Whether bad debt socialisation starts enabled; see `setSocialiseBadDebt`.
    /// @param jsonPayload Initial JSON metadata payload.
    /// @param initialPools Initial pools to list as active.
    function initialize(
        address loanEvaluator_,
        address liquidationEngine_,
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
        string calldata jsonPayload,
        address[] calldata initialPools
    ) external initializer {
        __AccessControlEnumerable_init();
        _initializeAuthorisable("LendingCore", "1");
        _initializeHookable(hookUpdater, initialHookReceiver, initialBeforeHookBitmap, initialAfterHookBitmap);

        _setLoanEvaluator(loanEvaluator_);
        _setLiquidationEngine(liquidationEngine_);
        _setSocialiseBadDebt(initialSocialiseBadDebt);
        _setMetadata(jsonPayload);

        /// @dev If both `defaultAdmin` and `poolLister` are the zero address, no further pools can be listed.
        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        if (poolLister != address(0)) _grantRole(POOL_LISTING_ROLE, poolLister);
        if (loanUpdater != address(0)) _grantRole(LOAN_UPDATER_ROLE, loanUpdater);
        if (liquidationUpdater != address(0)) _grantRole(LIQUIDATION_UPDATER_ROLE, liquidationUpdater);
        if (badDebtConfigurator != address(0)) _grantRole(BAD_DEBT_CONFIG_ROLE, badDebtConfigurator);
        if (metadataConfigurator != address(0)) _grantRole(METADATA_CONFIG_ROLE, metadataConfigurator);

        for (uint256 i; i < initialPools.length; ++i) {
            _addPool(initialPools[i]);
        }
    }

    /// @notice Sets the loan evaluator used to assess loan health.
    /// @dev Reverts if `newLoanEvaluator` does not support `ILoanEvaluator`.
    /// @param newLoanEvaluator New loan evaluator.
    function setLoanEvaluator(address newLoanEvaluator) external onlyRole(LOAN_UPDATER_ROLE) {
        _setLoanEvaluator(newLoanEvaluator);
    }

    /// @notice Sets the liquidation engine used to compute liquidations.
    /// @dev Reverts if `newLiquidationEngine` does not support `ILiquidationEngine`.
    /// @param newLiquidationEngine New liquidation engine.
    function setLiquidationEngine(address newLiquidationEngine) external onlyRole(LIQUIDATION_UPDATER_ROLE) {
        _setLiquidationEngine(newLiquidationEngine);
    }

    /// @notice Enables or disables bad debt socialisation.
    /// @dev Reverts if bad debt socialisation already has the requested status. Disabling it does not avoid the loss,
    ///      only defers it: the debt stays in the pool as an asset that will never be repaid, and keeps accruing
    ///      interest, so the share price overstates what the pool holds and the last depositors to redeem bear the
    ///      whole of it, unless someone covers the loss by repaying the debt through `repay`.
    /// @param enabled True to enable bad debt socialisation, false to disable it.
    function setSocialiseBadDebt(bool enabled) external onlyRole(BAD_DEBT_CONFIG_ROLE) {
        if (enabled == _socialiseBadDebt) revert SocialiseBadDebtUnchanged(enabled);

        _setSocialiseBadDebt(enabled);
    }

    /// @inheritdoc ILendingCore
    function setMetadata(string calldata jsonPayload) external onlyRole(METADATA_CONFIG_ROLE) {
        _setMetadata(jsonPayload);
    }

    /// @notice Adds `pool` to the pool listing, making it available for user operations.
    /// @dev Reverts if `pool` does not support `IPool` or is already listed. Listing is permanent and raises the gas of
    ///      every loan check; see `_addPool`.
    /// @param pool The pool to add.
    function addPool(address pool) external onlyRole(POOL_LISTING_ROLE) {
        _addPool(pool);
    }

    /// @notice Sets whether a listed `pool` is deprecated.
    /// @dev A deprecated pool remains listed and enumerable but is wound down. Reverts if `pool` is not listed or
    ///      already has the requested deprecation status.
    /// @param pool The pool to update.
    /// @param deprecated True to deprecate the pool, false to reactivate it.
    function setDeprecatePool(address pool, bool deprecated) external onlyRole(POOL_LISTING_ROLE) {
        (bool exists, uint256 status) = _pools.tryGet(pool);
        if (!exists) revert PoolNotListed(pool);
        if (deprecated == (status == uint256(PoolStatus.DEPRECATED))) revert PoolDeprecatedUnchanged(pool, deprecated);

        _pools.set(pool, uint256(deprecated ? PoolStatus.DEPRECATED : PoolStatus.ACTIVE));
        emit PoolDeprecationSet(pool, deprecated);
    }

    /// @inheritdoc ILendingCore
    /// @dev Requires no authorisation from `onBehalfOf`, since crediting collateral only improves its loan.
    function depositCollateral(IPool pool, uint256 assets, uint256 shares, address onBehalfOf)
        external
        nonReentrant
        returns (uint256 assetsDeposited, uint256 sharesMinted)
    {
        _fireHook(
            Phase.BEFORE,
            ActionLib.LC_DEPOSIT_COLLATERAL,
            abi.encode(onBehalfOf, msg.sender, msg.sender, pool, assets, shares)
        );

        _requirePoolActive(pool);
        (assetsDeposited, sharesMinted) = pool.depositCollateral(msg.sender, assets, shares, onBehalfOf);

        emit CollateralDeposited(pool, onBehalfOf, msg.sender, assetsDeposited, sharesMinted);

        _fireHook(
            Phase.AFTER,
            ActionLib.LC_DEPOSIT_COLLATERAL,
            abi.encode(onBehalfOf, msg.sender, msg.sender, pool, assetsDeposited, sharesMinted)
        );
    }

    /// @inheritdoc ILendingCore
    /// @dev Reverts unless the caller is `onBehalfOf` or authorised by it.
    function withdrawCollateral(IPool pool, uint256 assets, uint256 shares, address onBehalfOf, address receiver)
        external
        nonReentrant
        returns (uint256 assetsWithdrawn, uint256 sharesBurned)
    {
        _requireSenderAuthorised(onBehalfOf);

        _fireHook(
            Phase.BEFORE,
            ActionLib.LC_WITHDRAW_COLLATERAL,
            abi.encode(onBehalfOf, receiver, msg.sender, pool, assets, shares)
        );

        _requirePoolListed(pool);
        (assetsWithdrawn, sharesBurned) = pool.withdrawCollateral(onBehalfOf, assets, shares, receiver);

        _requireLoanHealthy(onBehalfOf);

        emit CollateralWithdrawn(pool, onBehalfOf, msg.sender, receiver, assetsWithdrawn, sharesBurned);

        _fireHook(
            Phase.AFTER,
            ActionLib.LC_WITHDRAW_COLLATERAL,
            abi.encode(onBehalfOf, receiver, msg.sender, pool, assetsWithdrawn, sharesBurned)
        );
    }

    /// @inheritdoc ILendingCore
    /// @dev Reverts unless the caller is `onBehalfOf` or authorised by it.
    function borrow(IPool pool, uint256 amount, address onBehalfOf, address receiver) external nonReentrant {
        _requireSenderAuthorised(onBehalfOf);

        _fireHook(Phase.BEFORE, ActionLib.LC_BORROW, abi.encode(onBehalfOf, receiver, msg.sender, pool, amount));

        _requirePoolActive(pool);
        pool.borrow(onBehalfOf, amount, receiver);

        _requireLoanHealthy(onBehalfOf);

        emit Borrowed(pool, onBehalfOf, msg.sender, receiver, amount);

        _fireHook(Phase.AFTER, ActionLib.LC_BORROW, abi.encode(onBehalfOf, receiver, msg.sender, pool, amount));
    }

    /// @inheritdoc ILendingCore
    /// @dev Requires no authorisation from `onBehalfOf`, since repaying its debt only improves its loan.
    function repay(IPool pool, uint256 amount, address onBehalfOf) external nonReentrant returns (uint256 repayment) {
        _fireHook(Phase.BEFORE, ActionLib.LC_REPAY, abi.encode(onBehalfOf, msg.sender, msg.sender, pool, amount));

        _requirePoolListed(pool);
        repayment = pool.repay(msg.sender, amount, onBehalfOf);

        emit Repaid(pool, onBehalfOf, msg.sender, repayment);

        _fireHook(Phase.AFTER, ActionLib.LC_REPAY, abi.encode(onBehalfOf, msg.sender, msg.sender, pool, repayment));
    }

    /// @inheritdoc ILendingCore
    /// @dev When bad debt socialisation is enabled and the liquidation leaves the violator with debt but no collateral
    ///      in any listed pool, the remaining debt is written off in every pool that carries it.
    ///
    ///      The loan has no collateral left when every collateral amount in underlying is zero, which is not the same
    ///      as the violator holding no collateral tokens. Once a pool's share price is below one, a share balance can
    ///      price to zero underlying, and such shares cannot be seized. A seizure names an amount of underlying and
    ///      must be non-zero, so even the smallest, of one unit, needs more shares than the violator holds. Checking
    ///      share balances would leave such a loan unable ever to socialise its debt. The violator instead keeps the
    ///      shares and can withdraw them once the debt is written off. They are worth less than one unit of underlying
    ///      at the write-off, and only dust however far the share price later recovers.
    function liquidate(address violator, LoanPosition[] calldata reqCols, LoanPosition[] calldata reqBors)
        external
        nonReentrant
    {
        _fireHook(Phase.BEFORE, ActionLib.LC_LIQUIDATE, abi.encode(violator, msg.sender, msg.sender, reqCols, reqBors));

        Loan memory loan = loanOf(violator);
        (bool liquidatable, uint256 health) = _loanEvaluator.isLoanLiquidatable(loan);
        if (!liquidatable) revert LoanNotLiquidatable(violator);

        /// @dev No explicit pool-listing check is needed on the positions below: `loan` is built only from the
        ///      violator's positions on listed pools, and the engine only acts on positions present in `loan`. A
        ///      requested position the loan does not hold is either rejected or returned with a zero amount, and zero
        ///      amounts are skipped below, so such a position never reaches a pool even where that pool is not listed.
        (LoanPosition[] memory cols, LoanPosition[] memory bors) =
            _liquidationEngine.liquidate(loan, health, reqCols, reqBors, _loanEvaluator);

        /// @dev Repay the violator's borrows on behalf of the liquidator, replacing each amount with the repayment the
        ///      pool applied. Zero amounts are skipped, since repaying nothing would still fire the pool's hooks.
        for (uint256 i = 0; i < bors.length; i++) {
            LoanPosition memory bor = bors[i];
            if (bor.amount == 0) continue;
            bor.amount = bor.pool.repay(msg.sender, bor.amount, violator);
            emit LiquidationRepaid(bor.pool, violator, msg.sender, bor.amount);
        }

        /// @dev Seize the violator's collateral rather than withdraw so that a pool settles it out of the position
        ///      itself rather than out of the liquidity it has available, replacing each amount with the underlying the
        ///      pool seized. Zero amounts are skipped, since seizing nothing would still fire the pool's hooks.
        for (uint256 i = 0; i < cols.length; i++) {
            LoanPosition memory col = cols[i];
            if (col.amount == 0) continue;
            uint256 sharesSeized;
            (col.amount, sharesSeized) = col.pool.seizeCollateral(violator, col.amount, msg.sender);
            emit CollateralSeized(col.pool, violator, msg.sender, col.amount, sharesSeized);
        }

        /// @dev Write off the violator's remaining debt in every pool that carries it once the loan holds no collateral
        ///      in any listed pool. The loan is read again after the seizures, so the check rests on what the pools
        ///      hold rather than on each pool settling a seizure to exactly the amount the engine named. `loanOf` lists
        ///      only non-zero positions, so an empty collateral list means every collateral amount in underlying is
        ///      zero.
        LoanPosition[] memory borsWrittenOff;
        if (_socialiseBadDebt) {
            ILendingCore.Loan memory loanAfter = loanOf(violator);
            if (loanAfter.collaterals.length == 0) {
                borsWrittenOff = loanAfter.borrows;
                for (uint256 i = 0; i < borsWrittenOff.length; i++) {
                    LoanPosition memory borWrittenOff = borsWrittenOff[i];
                    borWrittenOff.amount = borWrittenOff.pool.writeOffDebt(violator);
                    emit BadDebtSocialised(borWrittenOff.pool, violator, msg.sender, borWrittenOff.amount);
                }
            }
        }

        emit Liquidated(violator, msg.sender, health);

        _fireHook(
            Phase.AFTER,
            ActionLib.LC_LIQUIDATE,
            abi.encode(violator, msg.sender, msg.sender, cols, bors, borsWrittenOff)
        );
    }

    /// @notice The lifecycle status of `pool`.
    /// @dev Returns `PoolStatus.NONE` for pools that are not listed; does not revert.
    /// @param pool The pool to query.
    /// @return The pool's `PoolStatus`: `NONE` if not listed, otherwise `ACTIVE` or `DEPRECATED`.
    function poolStatus(address pool) external view returns (PoolStatus) {
        (bool exists, uint256 status) = _pools.tryGet(pool);
        return exists ? PoolStatus(status) : PoolStatus.NONE;
    }

    /// @notice Whether `pool` is listed (active or deprecated).
    /// @param pool The pool to query.
    /// @return True if the pool is listed, false otherwise.
    function isPoolAdded(address pool) external view returns (bool) {
        return _pools.contains(pool);
    }

    /// @notice All listed pools, each paired with its status.
    /// @return infos The listed pools and their statuses.
    function pools() external view returns (PoolInfo[] memory infos) {
        uint256 count = _pools.length();
        infos = new PoolInfo[](count);
        for (uint256 i; i < count; ++i) {
            (address pool, uint256 status) = _pools.at(i);
            infos[i] = PoolInfo({pool: pool, status: PoolStatus(status)});
        }
    }

    /// @inheritdoc ILendingCore
    function loanEvaluator() external view returns (address) {
        return address(_loanEvaluator);
    }

    /// @inheritdoc ILendingCore
    function liquidationEngine() external view returns (address) {
        return address(_liquidationEngine);
    }

    /// @notice Whether bad debt socialisation is enabled.
    /// @return True if a liquidation that leaves the violator with debt but no collateral writes that debt off.
    function socialiseBadDebt() external view returns (bool) {
        return _socialiseBadDebt;
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "LendingCore";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IERC165, AccessControlEnumerableUpgradeable, Authorisable)
        returns (bool)
    {
        return interfaceId == type(ILendingCore).interfaceId || interfaceId == type(IVersioned).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc ILendingCore
    function loanOf(address account) public view returns (Loan memory loan) {
        loan.account = account;

        uint256 poolCount = _pools.length();
        LoanPosition[] memory collaterals = new LoanPosition[](poolCount);
        LoanPosition[] memory borrows = new LoanPosition[](poolCount);
        uint256 collateralCount;
        uint256 borrowCount;

        for (uint256 i; i < poolCount; ++i) {
            (address poolAddress,) = _pools.at(i);
            IPool pool = IPool(poolAddress);

            uint256 collateral = pool.collateralOf(account);
            if (collateral != 0) collaterals[collateralCount++] = LoanPosition({pool: pool, amount: collateral});

            uint256 debt = pool.debtOf(account);
            if (debt != 0) borrows[borrowCount++] = LoanPosition({pool: pool, amount: debt});
        }

        loan.collaterals = collaterals.truncate(collateralCount);
        loan.borrows = borrows.truncate(borrowCount);
    }

    /// @notice Sets the loan evaluator, validating it supports the expected interface.
    /// @param  newLoanEvaluator  Loan evaluator used to assess loan health
    function _setLoanEvaluator(address newLoanEvaluator) internal {
        if (!ERC165Checker.supportsInterface(newLoanEvaluator, type(ILoanEvaluator).interfaceId)) {
            revert InvalidLoanEvaluator(newLoanEvaluator);
        }

        address oldLoanEvaluator = address(_loanEvaluator);
        _loanEvaluator = ILoanEvaluator(newLoanEvaluator);
        emit LoanEvaluatorSet(oldLoanEvaluator, newLoanEvaluator);
    }

    /// @notice Sets the liquidation engine, validating it supports the expected interface.
    /// @param  newLiquidationEngine  Liquidation engine used to compute liquidations
    function _setLiquidationEngine(address newLiquidationEngine) internal {
        if (!ERC165Checker.supportsInterface(newLiquidationEngine, type(ILiquidationEngine).interfaceId)) {
            revert InvalidLiquidationEngine(newLiquidationEngine);
        }

        address oldLiquidationEngine = address(_liquidationEngine);
        _liquidationEngine = ILiquidationEngine(newLiquidationEngine);
        emit LiquidationEngineSet(oldLiquidationEngine, newLiquidationEngine);
    }

    /// @notice Sets whether bad debt socialisation is enabled.
    /// @param  enabled Whether bad debt socialisation is enabled.
    function _setSocialiseBadDebt(bool enabled) internal {
        _socialiseBadDebt = enabled;
        emit BadDebtSocialisationSet(enabled);
    }

    /// @notice Emits new lending app metadata.
    /// @param jsonPayload New JSON metadata payload.
    function _setMetadata(string calldata jsonPayload) internal {
        emit MetadataSet(jsonPayload);
    }

    /// @dev Does not check that the `pool` is bound to `this` contract. Every listed pool, deprecated or not, adds two
    ///      external calls to each loan built by `loanOf`, and so to every withdrawal, borrow and liquidation. Pools
    ///      cannot be delisted so the cost only grows. It's the lister's responsibility to ensure a reasonable length.
    function _addPool(address pool) internal {
        if (!ERC165Checker.supportsInterface(pool, type(IPool).interfaceId)) revert InvalidPool(pool);
        if (_pools.contains(pool)) revert PoolAlreadyAdded(pool);

        _pools.set(pool, uint256(PoolStatus.ACTIVE));
        emit PoolAdded(pool);
    }

    /// @dev Reverts unless `pool` is listed. Deprecated pools are allowed so positions can be wound down.
    function _requirePoolListed(IPool pool) internal view {
        if (!_pools.contains(address(pool))) revert PoolNotListed(address(pool));
    }

    /// @dev Reverts unless `pool` is listed and active (not deprecated).
    function _requirePoolActive(IPool pool) internal view {
        (bool exists, uint256 status) = _pools.tryGet(address(pool));
        if (!exists) revert PoolNotListed(address(pool));
        if (status == uint256(PoolStatus.DEPRECATED)) revert PoolDeprecated(address(pool));
    }

    /// @dev Reverts unless the loan evaluator finds `account`'s loan healthy.
    function _requireLoanHealthy(address account) internal view {
        if (!_loanEvaluator.isLoanHealthy(loanOf(account))) revert LoanUnhealthy(account);
    }
}
