// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IVersioned} from "../interfaces/IVersioned.sol";
import {ILendingCore} from "../lending-core/interfaces/ILendingCore.sol";
import {LoanPositionLib} from "../lib/LoanPositionLib.sol";
import {MathUtils} from "../lib/MathUtils.sol";
import {ILoanEvaluator} from "../loan/interfaces/ILoanEvaluator.sol";
import {OracleConsumer} from "../oracle-consumer/abstract/OracleConsumer.sol";
import {IPool} from "../pool/interfaces/IPool.sol";
import {ILiquidationEngine} from "./interfaces/ILiquidationEngine.sol";

/// @title TargetHealthLiquidationEngine
/// @notice Liquidation engine for partial liquidations, where the liquidator chooses which borrows to repay and which
///         collaterals to seize, earns a bonus on the collateral that grows as the loan's health falls, and is limited
///         in size by the health the loan must be left at.
/// @dev The engine validates the liquidator's request rather than sizing the liquidation itself: the liquidator names
///      exact collateral amounts and maximum repayments, and the engine either accepts them unchanged or reverts. It
///      never reallocates between positions, so no allocation policy is encoded here and the search for the most
///      profitable liquidation stays off-chain.
///
///      A request is accepted when all of the following hold:
///
///      1. Entitlement. Every unit of value repaid entitles the liquidator to `1 + bonus` units of collateral value,
///         where the bonus belongs to the collateral being seized. Because each collateral carries its own bonus, the
///         check is expressed as the repayment value each seizure consumes:
///         `sum(seizeValue / (1 + bonus)) <= sum(repayValue)`. Claiming less than the entitlement is allowed and the
///         remainder is forfeited, which only ever benefits the violator.
///      2. Close-out. A liquidation that repays every borrow is not bounded by the target, since a loan with no
///         debt is at maximum health, so it is allowed only on a loan that owes at most `closeOutThreshold`. A
///         larger loan must first be brought down by partial liquidations, and since the threshold is above
///         `minLeftoverValue`, they can always leave it owing an amount a close-out then accepts. A close-out may
///         still repay more than a partial liquidation to the target would have, but never more than the threshold.
///      3. Target health. Unless the liquidation repays every borrow, the loan's health after it must not exceed
///         `targetHealthFactor`, which is what bounds the size of a liquidation.
///      4. Dust. The liquidation must leave the loan with no borrows, or no collateral, or at least `minLeftoverValue`
///         of each, so that no loan is left too small to be worth liquidating again.
///
///      The engine values positions with its own oracle and reads health from the loan evaluator, so it depends on
///      three configurations it does not own. Nothing enforces any of them; it is the configuring admin's
///      responsibility to keep them consistent with the evaluator.
///
///      - Pricing. Its oracle should be the same one the loan evaluator uses. An engine priced differently to the
///        evaluator would pay bonuses computed on prices that disagree with the health the liquidation is measured
///        against.
///      - Health semantics. `targetHealthFactor` and the ramp bounds are compared directly against
///        `ILoanEvaluator.getLoanHealth`, which the interface defines only as "higher is better". This engine requires
///        an evaluator whose health is 18dp and whose solvency boundary is `1e18`.
///      - Bonuses. A liquidation takes collateral worth `1 + bonus` times the debt it clears, so it raises the loan's
///        health only while the loan's collateral is worth more than `1 + bonus` times its debt. Below that, every
///        liquidation lowers health, the target health check cannot bound its size, and the loan cannot be closed out
///        without leaving bad debt. That is expected of a loan that has fallen deep into liquidation, but each bonus
///        must be small enough that a loan at the solvency boundary is still above it. For an evaluator that discounts
///        each collateral's value by a factor `f` and values debt at par, that means `f * (1 + maxBonus) < 1` for every
///        collateral, or the equivalent under the evaluator's own weighting. Otherwise a loan that has only just become
///        liquidatable cannot be closed out without leaving bad debt. Anyone can extract it by borrowing to their limit
///        and liquidating themselves once the loan tips over, which may take no more than accrued interest, repeatably
///        and at any size.
///
///      Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract TargetHealthLiquidationEngine is ILiquidationEngine, OracleConsumer {
    using LoanPositionLib for ILendingCore.LoanPosition[];
    using Math for uint256;

    /// @notice The bonus a collateral pays a liquidator, as a fraction of the value repaid, with 4 decimals.
    /// @dev The bonus ramps linearly from `minBonus` to `maxBonus` as health falls across the ramp bounds, so a riskier
    ///      collateral is configured with a larger `maxBonus`.
    /// @param minBonus Bonus paid at or above `bonusRampStartHealth`.
    /// @param maxBonus Bonus paid at or below `bonusRampEndHealth`; at least `minBonus`.
    /// @param isAdded Whether the collateral has been configured.
    struct CollateralBonus {
        uint16 minBonus;
        uint16 maxBonus;
        bool isAdded;
    }

    /// @notice Initial bonus configuration for a collateral.
    /// @param pool Pool to configure.
    /// @param minBonus Bonus paid at or above `bonusRampStartHealth`, with 4 decimals.
    /// @param maxBonus Bonus paid at or below `bonusRampEndHealth`, with 4 decimals.
    struct CollateralBonusConfig {
        IPool pool;
        uint16 minBonus;
        uint16 maxBonus;
    }

    /// @notice Role allowed to change the liquidation parameters.
    bytes32 public constant LIQUIDATION_CONFIG_ROLE = keccak256("LIQUIDATION_CONFIG_ROLE");

    uint256 private _targetHealthFactor; // 18dp, >= 1e18
    uint256 private _bonusRampStartHealth; // 18dp, > _bonusRampEndHealth, <= 1e18
    uint256 private _bonusRampEndHealth; // 18dp
    uint256 private _minLeftoverValue; // oracle numeraire, < _closeOutThreshold
    uint256 private _closeOutThreshold; // oracle numeraire, > _minLeftoverValue
    mapping(IPool pool => CollateralBonus) private _bonuses;

    /// @notice Emitted when the target health factor is updated.
    event TargetHealthFactorUpdated(uint256 oldTargetHealthFactor, uint256 newTargetHealthFactor);
    /// @notice Emitted when the bonus ramp bounds are updated.
    event BonusRampUpdated(uint256 oldStartHealth, uint256 oldEndHealth, uint256 newStartHealth, uint256 newEndHealth);
    /// @notice Emitted when the minimum leftover value is updated.
    event MinLeftoverValueUpdated(uint256 oldMinLeftoverValue, uint256 newMinLeftoverValue);
    /// @notice Emitted when the close-out threshold is updated.
    event CloseOutThresholdUpdated(uint256 oldCloseOutThreshold, uint256 newCloseOutThreshold);
    /// @notice Emitted when a collateral is configured for the first time.
    event PoolAdded(IPool indexed pool, uint16 minBonus, uint16 maxBonus);
    /// @notice Emitted when a configured collateral's bonuses are updated.
    event PoolBonusesUpdated(
        IPool indexed pool, uint16 oldMinBonus, uint16 oldMaxBonus, uint16 newMinBonus, uint16 newMaxBonus
    );

    /// @notice Thrown when configuring a pool that is already configured.
    error PoolAlreadyAdded(IPool pool);
    /// @notice Thrown when a pool has no bonus configuration.
    error PoolUnknown(IPool pool);
    /// @notice Thrown when the target health factor would leave a liquidated loan below the solvency boundary.
    error TargetHealthFactorTooLow(uint256 targetHealthFactor);
    /// @notice Thrown when a collateral's minimum bonus exceeds its maximum bonus.
    error BonusRangeInvalid(uint16 minBonus, uint16 maxBonus);
    /// @notice Thrown when the ramp does not fall, i.e. its start health is not above its end health.
    error BonusRampInvalid(uint256 startHealth, uint256 endHealth);
    /// @notice Thrown when the ramp starts above the solvency boundary, where no loan is liquidatable, so that no
    ///         liquidation could ever be paid the minimum bonus.
    error BonusRampStartTooHigh(uint256 startHealth);
    /// @notice Thrown when the close-out threshold would not be above the minimum leftover value, which would leave no
    ///         loan size that partial liquidations can reach and that a close-out then accepts.
    error CloseOutWindowEmpty(uint256 minLeftoverValue, uint256 closeOutThreshold);

    /// @notice Thrown when `reqCols` names the same pool more than once.
    error DuplicateRequestedCollateral();
    /// @notice Thrown when `reqBors` names the same pool more than once.
    error DuplicateRequestedBorrow();
    /// @notice Thrown when the loan holds less collateral than the liquidator requested to seize.
    /// @param pool The pool whose collateral falls short.
    /// @param reqAmount The amount the liquidator requested to seize.
    /// @param loanAmount The amount the loan actually holds.
    error InsufficientCollateral(IPool pool, uint256 reqAmount, uint256 loanAmount);
    /// @notice Thrown when a request repays nothing, since a liquidation that repays no debt is entitled to no
    ///         collateral and can only leave the loan as it found it.
    error NoRepayment();
    /// @notice Thrown when the repayment does not cover the collateral requested at the ruling bonuses.
    /// @param repayValue The value of the requested repayments.
    /// @param requiredValue The repayment value the requested seizures consume.
    error InsufficientRepayment(uint256 repayValue, uint256 requiredValue);
    /// @notice Thrown when the liquidation would repay every borrow of a loan that owes more than the close-out
    ///         threshold, which must instead be brought down by partial liquidations first.
    /// @param borrowValue The value of the borrows the loan owes.
    /// @param closeOutThreshold The maximum value of borrows a liquidation may repay in full.
    error CloseOutTooLarge(uint256 borrowValue, uint256 closeOutThreshold);
    /// @notice Thrown when the liquidation would leave the loan healthier than the target, i.e. it repays too much.
    /// @param healthAfter The health the loan would be left at.
    /// @param targetHealthFactor The maximum health a liquidation may leave the loan at.
    error TargetHealthExceeded(uint256 healthAfter, uint256 targetHealthFactor);
    /// @notice Thrown when the liquidation would leave the loan with too little of both sides to be worth liquidating
    ///         again, rather than closing out one side of it.
    /// @param remainingCollateralValue The value of the collateral the loan would be left holding.
    /// @param remainingBorrowValue The value of the borrows the loan would be left owing.
    error MustNotLeaveDust(uint256 remainingCollateralValue, uint256 remainingBorrowValue);

    /// @notice Locks the implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a clone with role members, oracle configuration, and initial liquidation parameters.
    /// @dev Callable once per clone. Reverts atomically if any parameter or collateral configuration is invalid.
    /// @param defaultAdmin Initial default admin role member.
    /// @param oracleUpdater Initial oracle updater role member.
    /// @param liquidationConfigurator Initial liquidation configurator role member.
    /// @param oracle_ Initial oracle.
    /// @param targetHealthFactor_ Initial target health factor with 18 decimals.
    /// @param bonusRampStartHealth_ Initial health at or above which collaterals pay their minimum bonus.
    /// @param bonusRampEndHealth_ Initial health at or below which collaterals pay their maximum bonus.
    /// @param minLeftoverValue_ Initial minimum leftover value in the oracle numeraire.
    /// @param closeOutThreshold_ Initial close-out threshold in the oracle numeraire.
    /// @param collateralBonusConfigs Initial collateral bonus configurations.
    function initialize(
        address defaultAdmin,
        address oracleUpdater,
        address liquidationConfigurator,
        address oracle_,
        uint256 targetHealthFactor_,
        uint256 bonusRampStartHealth_,
        uint256 bonusRampEndHealth_,
        uint256 minLeftoverValue_,
        uint256 closeOutThreshold_,
        CollateralBonusConfig[] calldata collateralBonusConfigs
    ) external initializer {
        __AccessControlEnumerable_init();
        _initializeOracleConsumer(oracleUpdater, oracle_);

        _updateTargetHealthFactor(targetHealthFactor_);
        _updateBonusRamp(bonusRampStartHealth_, bonusRampEndHealth_);
        // The threshold goes first: each is validated against the other's stored value, and both start at zero.
        _updateCloseOutThreshold(closeOutThreshold_);
        _updateMinLeftoverValue(minLeftoverValue_);

        for (uint256 i; i < collateralBonusConfigs.length; ++i) {
            CollateralBonusConfig calldata config = collateralBonusConfigs[i];
            _addPool(config.pool, config.minBonus, config.maxBonus);
        }

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        if (liquidationConfigurator != address(0)) _grantRole(LIQUIDATION_CONFIG_ROLE, liquidationConfigurator);
    }

    /// @notice Updates the maximum health a liquidation may leave the loan at.
    /// @dev Raising it allows larger liquidations, since a liquidation is bounded by the health it leaves behind.
    /// @param newTargetHealthFactor New target health factor with 18 decimals; at least `1e18`.
    function updateTargetHealthFactor(uint256 newTargetHealthFactor) external onlyRole(LIQUIDATION_CONFIG_ROLE) {
        _updateTargetHealthFactor(newTargetHealthFactor);
    }

    /// @notice Updates the health bounds the bonus ramps across.
    /// @dev Both bounds move together because the ramp is only meaningful as a falling interval.
    /// @param newStartHealth New health at or above which collaterals pay their minimum bonus, with 18 decimals; at
    ///        most `1e18`. Since no loan is liquidatable above `1e18`: a ramp starting higher would pay every
    ///        liquidation more than the minimum bonus.
    /// @param newEndHealth New health at or below which collaterals pay their maximum bonus, with 18 decimals.
    function updateBonusRamp(uint256 newStartHealth, uint256 newEndHealth) external onlyRole(LIQUIDATION_CONFIG_ROLE) {
        _updateBonusRamp(newStartHealth, newEndHealth);
    }

    /// @notice Updates the value of collateral and of borrows a partial liquidation must leave the loan with.
    /// @dev Setting it to zero disables the dust rule, since a loan can never be left with a negative value. It must
    ///      stay below the close-out threshold, so raising it may first require raising the threshold.
    /// @param newMinLeftoverValue New minimum leftover value in the oracle numeraire; below the close-out threshold.
    function updateMinLeftoverValue(uint256 newMinLeftoverValue) external onlyRole(LIQUIDATION_CONFIG_ROLE) {
        _updateMinLeftoverValue(newMinLeftoverValue);
    }

    /// @notice Updates the maximum value of borrows a liquidation may repay in full.
    /// @dev Raising it allows larger loans to be closed out in one liquidation, each of which may repay more than a
    ///      partial liquidation to the target would have. It should sit comfortably above the minimum leftover value,
    ///      e.g. twice it, so that a loan left at the dust floor can still be closed out after prices move or when a
    ///      borrow's base unit is worth a lot.
    /// @param newCloseOutThreshold New close-out threshold in the oracle numeraire; above the minimum leftover value.
    function updateCloseOutThreshold(uint256 newCloseOutThreshold) external onlyRole(LIQUIDATION_CONFIG_ROLE) {
        _updateCloseOutThreshold(newCloseOutThreshold);
    }

    /// @notice Configures a pool as collateral this engine can seize.
    /// @dev Collateral the engine has no configuration for cannot be seized, so this set should track the collateral
    ///      the paired loan evaluator recognises.
    /// @param pool Pool to configure.
    /// @param minBonus Bonus paid at or above the ramp's start health, with 4 decimals.
    /// @param maxBonus Bonus paid at or below the ramp's end health, with 4 decimals.
    function addPool(IPool pool, uint16 minBonus, uint16 maxBonus) external onlyRole(LIQUIDATION_CONFIG_ROLE) {
        _addPool(pool, minBonus, maxBonus);
    }

    /// @notice Updates a configured collateral's bonuses.
    /// @dev Both bonuses move together because they are only meaningful as the two ends of one ramp.
    /// @param pool Pool to update.
    /// @param newMinBonus New bonus paid at or above the ramp's start health, with 4 decimals.
    /// @param newMaxBonus New bonus paid at or below the ramp's end health, with 4 decimals.
    function updatePoolBonuses(IPool pool, uint16 newMinBonus, uint16 newMaxBonus)
        external
        onlyRole(LIQUIDATION_CONFIG_ROLE)
    {
        _checkBonusRange(newMinBonus, newMaxBonus);

        CollateralBonus storage collateralBonus = _getCollateralBonusStorage(pool);
        uint16 oldMinBonus = collateralBonus.minBonus;
        uint16 oldMaxBonus = collateralBonus.maxBonus;
        collateralBonus.minBonus = newMinBonus;
        collateralBonus.maxBonus = newMaxBonus;

        emit PoolBonusesUpdated(pool, oldMinBonus, oldMaxBonus, newMinBonus, newMaxBonus);
    }

    /// @inheritdoc ILiquidationEngine
    /// @dev Seizes and repays exactly what the resolved request names, so both returned arrays are bounded by the
    ///      request. `reqCols` amounts are exact, with `type(uint256).max` naming the whole position, and are rejected
    ///      if the loan holds less. `reqBors` amounts are maximums capped at what the loan owes, which keeps a request
    ///      valid when debt has accrued or been repaid since it was made.
    ///
    ///      A borrow the loan does not hold is ignored rather than rejected, since a third party may have repaid it
    ///      since the request was made and rejecting it would let anyone invalidate a pending liquidation for dust. A
    ///      collateral the loan does not hold is treated as a position of zero, so any non-zero exact amount is
    ///      rejected, as the liquidator cannot be paid out of it, and `type(uint256).max` resolves to zero. Were the
    ///      latter rejected, a pending liquidation that seizes every collateral could be invalidated by a dust deposit,
    ///      landing before it, into a pool the loan did not hold when the request was made, since the collateral left
    ///      behind would subject the liquidation to the dust rule. Naming every pool with `type(uint256).max` sweeps
    ///      such a deposit up instead. Collateral the loan holds but the request omits is simply left alone, this
    ///      engine being partial.
    ///
    ///      Each returned array holds one entry per request, in the order requested, so a request that resolves to
    ///      nothing is returned with a zero amount for the caller to skip rather than dropped.
    function liquidate(
        ILendingCore.Loan calldata loan,
        uint256 health,
        ILendingCore.LoanPosition[] calldata reqCols,
        ILendingCore.LoanPosition[] calldata reqBors,
        ILoanEvaluator loanEvaluator
    )
        external
        view
        returns (ILendingCore.LoanPosition[] memory colsToSeize, ILendingCore.LoanPosition[] memory borsToRepay)
    {
        ILendingCore.LoanPosition[] memory remainingCols;
        ILendingCore.LoanPosition[] memory remainingBors;
        (colsToSeize, remainingCols) = _resolveSeizures(loan.collaterals, reqCols);
        (borsToRepay, remainingBors) = _resolveRepayments(loan.borrows, reqBors);

        uint256 repayValue = _checkEntitlement(colsToSeize, borsToRepay, health);

        ILendingCore.Loan memory loanAfter =
            ILendingCore.Loan({account: loan.account, collaterals: remainingCols, borrows: remainingBors});
        bool noBorrowsLeft = _isEmpty(remainingBors);
        bool noCollateralLeft = _isEmpty(remainingCols);

        /// @dev A liquidation that repays every borrow is held to the close-out threshold instead of the target. An
        ///      evaluator reports a loan with no debt at maximum health, so holding it to the target would make closing
        ///      a loan out entirely impossible. Its repayments are capped at what the loan owes, so `repayValue` is the
        ///      value of every borrow. It is exempt from the dust rule, since nothing is left to strand. Seizing every
        ///      collateral is exempt from the dust rule for the same reason: nothing is then left to pay what the loan
        ///      still owes, so there is nothing left to liquidate either way.
        if (noBorrowsLeft) {
            _checkCloseOut(repayValue);
        } else {
            _checkTargetHealth(loanAfter, loanEvaluator);
            if (!noCollateralLeft) _checkDust(loanAfter);
        }
    }

    /// @notice The maximum health a liquidation may leave the loan at, with 18 decimals.
    /// @return The target health factor.
    function targetHealthFactor() external view returns (uint256) {
        return _targetHealthFactor;
    }

    /// @notice The health bounds the bonus ramps across, with 18 decimals.
    /// @return startHealth The health at or above which collaterals pay their minimum bonus.
    /// @return endHealth The health at or below which collaterals pay their maximum bonus.
    function bonusRamp() external view returns (uint256 startHealth, uint256 endHealth) {
        return (_bonusRampStartHealth, _bonusRampEndHealth);
    }

    /// @notice The value of collateral and of borrows a partial liquidation must leave the loan with, in the oracle
    ///         numeraire.
    /// @return The minimum leftover value.
    function minLeftoverValue() external view returns (uint256) {
        return _minLeftoverValue;
    }

    /// @notice The maximum value of borrows a liquidation may repay in full, in the oracle numeraire.
    /// @return The close-out threshold.
    function closeOutThreshold() external view returns (uint256) {
        return _closeOutThreshold;
    }

    /// @notice The bonus configuration of a collateral.
    /// @dev Reverts if `pool` is not configured.
    /// @param pool The pool to query.
    /// @return The pool's bonus configuration.
    function getCollateralBonus(IPool pool) external view returns (CollateralBonus memory) {
        return _getCollateralBonusStorage(pool);
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "TargetHealthLiquidationEngine";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IERC165, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return interfaceId == type(ILiquidationEngine).interfaceId || interfaceId == type(IVersioned).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @notice Whether a pool has been configured as collateral this engine can seize.
    /// @param pool The pool to query.
    /// @return True if the pool is configured, false otherwise.
    function isPoolAdded(IPool pool) public view returns (bool) {
        return _bonuses[pool].isAdded;
    }

    /// @dev Configures a pool that has never been configured before.
    /// @param pool Pool to configure.
    /// @param minBonus Bonus paid at or above the ramp's start health, with 4 decimals.
    /// @param maxBonus Bonus paid at or below the ramp's end health, with 4 decimals.
    function _addPool(IPool pool, uint16 minBonus, uint16 maxBonus) internal {
        if (isPoolAdded(pool)) revert PoolAlreadyAdded(pool);
        _checkBonusRange(minBonus, maxBonus);

        _bonuses[pool] = CollateralBonus({minBonus: minBonus, maxBonus: maxBonus, isAdded: true});

        emit PoolAdded(pool, minBonus, maxBonus);
    }

    /// @dev Validates and stores the target health factor.
    /// @param newTargetHealthFactor New target health factor with 18 decimals.
    function _updateTargetHealthFactor(uint256 newTargetHealthFactor) internal {
        if (newTargetHealthFactor < MathUtils.ONE_18_DP) revert TargetHealthFactorTooLow(newTargetHealthFactor);

        uint256 oldTargetHealthFactor = _targetHealthFactor;
        _targetHealthFactor = newTargetHealthFactor;

        emit TargetHealthFactorUpdated(oldTargetHealthFactor, newTargetHealthFactor);
    }

    /// @dev Validates and stores the bonus ramp bounds.
    /// @param newStartHealth New health at or above which collaterals pay their minimum bonus, with 18 decimals.
    /// @param newEndHealth New health at or below which collaterals pay their maximum bonus, with 18 decimals.
    function _updateBonusRamp(uint256 newStartHealth, uint256 newEndHealth) internal {
        if (newStartHealth <= newEndHealth) revert BonusRampInvalid(newStartHealth, newEndHealth);
        if (newStartHealth > MathUtils.ONE_18_DP) revert BonusRampStartTooHigh(newStartHealth);

        uint256 oldStartHealth = _bonusRampStartHealth;
        uint256 oldEndHealth = _bonusRampEndHealth;
        _bonusRampStartHealth = newStartHealth;
        _bonusRampEndHealth = newEndHealth;

        emit BonusRampUpdated(oldStartHealth, oldEndHealth, newStartHealth, newEndHealth);
    }

    /// @dev Validates and stores the minimum leftover value.
    /// @param newMinLeftoverValue New minimum leftover value in the oracle numeraire.
    function _updateMinLeftoverValue(uint256 newMinLeftoverValue) internal {
        _checkCloseOutWindow(newMinLeftoverValue, _closeOutThreshold);

        uint256 oldMinLeftoverValue = _minLeftoverValue;
        _minLeftoverValue = newMinLeftoverValue;

        emit MinLeftoverValueUpdated(oldMinLeftoverValue, newMinLeftoverValue);
    }

    /// @dev Validates and stores the close-out threshold.
    /// @param newCloseOutThreshold New close-out threshold in the oracle numeraire.
    function _updateCloseOutThreshold(uint256 newCloseOutThreshold) internal {
        _checkCloseOutWindow(_minLeftoverValue, newCloseOutThreshold);

        uint256 oldCloseOutThreshold = _closeOutThreshold;
        _closeOutThreshold = newCloseOutThreshold;

        emit CloseOutThresholdUpdated(oldCloseOutThreshold, newCloseOutThreshold);
    }

    /// @dev Returns a configured collateral's bonuses, reverting if the pool has never been configured.
    /// @param pool The pool to look up.
    /// @return collateralBonus The pool's stored bonus configuration.
    function _getCollateralBonusStorage(IPool pool) internal view returns (CollateralBonus storage collateralBonus) {
        collateralBonus = _bonuses[pool];
        if (!collateralBonus.isAdded) revert PoolUnknown(pool);
    }

    /// @dev Reverts unless a collateral's bonuses form a rising range the ramp can interpolate across.
    /// @param minBonus Bonus paid at or above the ramp's start health, with 4 decimals.
    /// @param maxBonus Bonus paid at or below the ramp's end health, with 4 decimals.
    function _checkBonusRange(uint16 minBonus, uint16 maxBonus) internal pure {
        if (minBonus > maxBonus) revert BonusRangeInvalid(minBonus, maxBonus);
    }

    /// @dev Reverts unless the close-out threshold is above the minimum leftover value, so that partial liquidations
    ///      can always bring a loan down to a size a close-out accepts.
    /// @param minLeftoverValue_ Minimum leftover value in the oracle numeraire.
    /// @param closeOutThreshold_ Close-out threshold in the oracle numeraire.
    function _checkCloseOutWindow(uint256 minLeftoverValue_, uint256 closeOutThreshold_) internal pure {
        if (closeOutThreshold_ <= minLeftoverValue_) revert CloseOutWindowEmpty(minLeftoverValue_, closeOutThreshold_);
    }

    /// @dev Reverts unless the repayment covers the collateral being seized at the bonuses ruling at `health`. Each
    ///      seizure is converted into the repayment value it consumes, `seizeValue / (1 + bonus)`, and the total
    ///      repayment must cover the total consumed. Repaying more than the seizures consume is allowed: the unclaimed
    ///      entitlement is forfeited, which costs only the liquidator.
    ///
    ///      Every rounding here runs against the liquidator, so the amounts it accepts never pay out more than the
    ///      bonus ruling at `health`: collateral is valued up, repayments are valued down, and the repayment value a
    ///      seizure consumes is rounded up.
    ///
    ///      Positions with a zero amount are skipped rather than valued. They consume and provide nothing either way.
    /// @param colsToSeize The collateral to seize.
    /// @param borsToRepay The borrows to repay.
    /// @param health The loan's health before the liquidation, which fixes the bonus each seizure earns.
    /// @return repayValue The value of the borrows to repay, rounded down.
    function _checkEntitlement(
        ILendingCore.LoanPosition[] memory colsToSeize,
        ILendingCore.LoanPosition[] memory borsToRepay,
        uint256 health
    ) private view returns (uint256 repayValue) {
        uint256 requiredValue;
        for (uint256 i; i < colsToSeize.length; ++i) {
            ILendingCore.LoanPosition memory colToSeize = colsToSeize[i];
            if (colToSeize.amount == 0) continue;

            uint256 bonus = _bonus(colToSeize.pool, health);
            requiredValue += _oracleValue(colToSeize.pool, colToSeize.amount, Math.Rounding.Ceil)
                .mulDiv(MathUtils.ONE_4_DP, MathUtils.ONE_4_DP + bonus, Math.Rounding.Ceil);
        }

        repayValue = _totalValue(borsToRepay);

        if (repayValue < requiredValue) revert InsufficientRepayment(repayValue, requiredValue);
    }

    /// @dev Reverts if a liquidation that repays every borrow closes out a loan that owes more than the close-out
    ///      threshold. Such a loan is at maximum health once it owes nothing, so the target cannot bound the
    ///      liquidation, and a smaller one might already have brought it to the target. It must instead be brought down
    ///      by partial liquidations, which the target does bound, until it owes no more than the threshold.
    /// @param borrowValue The value of the borrows the loan owes, rounded down.
    function _checkCloseOut(uint256 borrowValue) private view {
        uint256 closeOutThreshold_ = _closeOutThreshold;
        if (borrowValue > closeOutThreshold_) revert CloseOutTooLarge(borrowValue, closeOutThreshold_);
    }

    /// @dev Reverts if the liquidation would leave the loan healthier than the target. This is what bounds how much of
    ///      a loan a single liquidation may close: the more it repays, the healthier what remains.
    ///
    ///      The health is measured on the loan this engine projects rather than the one the pools will settle to, so
    ///      the two can differ by whatever a pool rounds converting the seized and repaid amounts into shares.
    /// @param loanAfter The loan as it would stand after the liquidation, which must still owe something.
    /// @param loanEvaluator The evaluator that measures the loan's health.
    function _checkTargetHealth(ILendingCore.Loan memory loanAfter, ILoanEvaluator loanEvaluator) private view {
        uint256 healthAfter = loanEvaluator.getLoanHealth(loanAfter);
        uint256 targetHealthFactor_ = _targetHealthFactor;
        if (healthAfter > targetHealthFactor_) revert TargetHealthExceeded(healthAfter, targetHealthFactor_);
    }

    /// @dev Reverts if the liquidation would leave the loan too small on either side to be worth liquidating again:
    ///      both must be left worth at least `minLeftoverValue`.
    ///
    ///      It reads the state the liquidation leaves rather than the state it changes, so a loan already below the
    ///      threshold can only be closed out, never trimmed further.
    ///
    ///      Both sides are valued down to make a borderline leftover count as dust.
    /// @param loanAfter The loan as it would stand after the liquidation, which must still hold both sides.
    function _checkDust(ILendingCore.Loan memory loanAfter) private view {
        uint256 minLeftoverValue_ = _minLeftoverValue;
        if (minLeftoverValue_ == 0) return;

        uint256 remainingCollateralValue = _totalValue(loanAfter.collaterals);
        uint256 remainingBorrowValue = _totalValue(loanAfter.borrows);

        if (remainingCollateralValue < minLeftoverValue_ || remainingBorrowValue < minLeftoverValue_) {
            revert MustNotLeaveDust(remainingCollateralValue, remainingBorrowValue);
        }
    }

    /// @dev The bonus a collateral pays at a given loan health: the collateral's minimum bonus at or above the ramp's
    ///      start health, its maximum bonus at or below the ramp's end health, and a linear interpolation between the
    ///      two in between. Rounded down, so a liquidator is never paid more than the ramp defines.
    /// @param pool The collateral being seized.
    /// @param health The loan's health before the liquidation, with 18 decimals.
    /// @return The bonus, as a fraction of the value repaid, with 4 decimals.
    function _bonus(IPool pool, uint256 health) private view returns (uint256) {
        CollateralBonus storage collateralBonus = _getCollateralBonusStorage(pool);

        uint256 startHealth = _bonusRampStartHealth;
        if (health >= startHealth) return collateralBonus.minBonus;

        uint256 endHealth = _bonusRampEndHealth;
        if (health <= endHealth) return collateralBonus.maxBonus;

        uint256 bonusRange = collateralBonus.maxBonus - collateralBonus.minBonus;
        return collateralBonus.minBonus + bonusRange.mulDiv(startHealth - health, startHealth - endHealth);
    }

    /// @dev The total value of a set of positions in the oracle numeraire, rounded down.
    /// @param positions The positions to value.
    /// @return total The summed value.
    function _totalValue(ILendingCore.LoanPosition[] memory positions) private view returns (uint256 total) {
        for (uint256 i; i < positions.length; ++i) {
            ILendingCore.LoanPosition memory position = positions[i];
            if (position.amount == 0) continue;

            total += _oracleValue(position.pool, position.amount, Math.Rounding.Floor);
        }
    }

    /// @dev Resolves the requested seizures against the collateral the loan holds. Amounts are exact:
    ///      `type(uint256).max` resolves to the whole position and anything above what the loan holds is rejected
    ///      rather than capped, so a liquidator is never handed less collateral than the amount they sized their
    ///      repayment against. A collateral the loan does not hold is treated as a position of zero, so
    ///      `type(uint256).max` resolves to nothing and any other non-zero amount is rejected.
    /// @param cols The loan's collateral positions.
    /// @param reqCols The requested collateral positions, whose amounts are exact or `type(uint256).max`.
    /// @return colsToSeize The collateral to seize, one entry per request in the order `reqCols` holds them.
    /// @return remainingCols The collateral the loan would be left holding, one entry per position in the order `cols`
    ///         holds them.
    function _resolveSeizures(ILendingCore.LoanPosition[] calldata cols, ILendingCore.LoanPosition[] calldata reqCols)
        private
        pure
        returns (ILendingCore.LoanPosition[] memory colsToSeize, ILendingCore.LoanPosition[] memory remainingCols)
    {
        if (reqCols.hasDuplicatePool()) {
            revert DuplicateRequestedCollateral();
        }

        colsToSeize = reqCols;
        remainingCols = cols;

        for (uint256 i; i < reqCols.length; ++i) {
            IPool pool = reqCols[i].pool;
            uint256 reqAmount = reqCols[i].amount;

            (bool found, uint256 index) = cols.findPosition(pool);
            uint256 colAmount = found ? cols[index].amount : 0;
            uint256 amount = reqAmount == type(uint256).max ? colAmount : reqAmount;
            if (amount > colAmount) revert InsufficientCollateral(pool, reqAmount, colAmount);

            colsToSeize[i].amount = amount;
            if (found) remainingCols[index].amount = colAmount - amount;
        }
    }

    /// @dev Resolves the requested repayments against the debt the loan owes. Amounts are maximums, capped at what the
    ///      loan owes, and a request naming a borrow the loan does not hold resolves to zero.
    /// @param bors The loan's borrow positions.
    /// @param reqBors The requested borrow positions, whose amounts are maximums.
    /// @return borsToRepay The borrows to repay, one entry per request in the order `reqBors` holds them.
    /// @return remainingBors The borrows the loan would be left owing, one entry per position in the order `bors` holds
    ///         them.
    function _resolveRepayments(ILendingCore.LoanPosition[] calldata bors, ILendingCore.LoanPosition[] calldata reqBors)
        private
        pure
        returns (ILendingCore.LoanPosition[] memory borsToRepay, ILendingCore.LoanPosition[] memory remainingBors)
    {
        if (reqBors.hasDuplicatePool()) {
            revert DuplicateRequestedBorrow();
        }

        borsToRepay = reqBors;
        remainingBors = bors;

        bool repaysAnything;

        for (uint256 i; i < reqBors.length; ++i) {
            (bool found, uint256 index) = bors.findPosition(reqBors[i].pool);
            uint256 borAmount = found ? bors[index].amount : 0;
            uint256 amount = Math.min(reqBors[i].amount, borAmount);

            borsToRepay[i].amount = amount;
            if (found) remainingBors[index].amount = borAmount - amount;

            if (amount != 0) repaysAnything = true;
        }

        if (!repaysAnything) revert NoRepayment();
    }

    /// @dev Whether a loan has been closed out on one side, i.e. none of its positions there hold anything.
    /// @param positions The positions to scan.
    /// @return True if no position holds a non-zero amount.
    function _isEmpty(ILendingCore.LoanPosition[] memory positions) private pure returns (bool) {
        for (uint256 i; i < positions.length; ++i) {
            if (positions[i].amount != 0) return false;
        }
        return true;
    }
}
