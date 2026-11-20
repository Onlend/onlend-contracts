// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {OracleConsumer} from "../oracle-consumer/abstract/OracleConsumer.sol";
import {MathUtils} from "../lib/MathUtils.sol";
import {IPool} from "../pool/interfaces/IPool.sol";
import {ILendingCore} from "../lending-core/interfaces/ILendingCore.sol";
import {ILoanEvaluator} from "./interfaces/ILoanEvaluator.sol";
import {IVersioned} from "../interfaces/IVersioned.sol";

/// @title FactorLoanEvaluator
/// @notice Over-collateralised loan evaluator that values a loan using per-pool collateral factors (which discount
///         collateral) and borrow factors (which inflate borrows).
/// @dev Health is the ratio effectiveCollateral / effectiveBorrow scaled to 18dp: a loan is healthy while its health is
///      at least minHealthFactor, and liquidatable once health drops below 1e18.
///      Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract FactorLoanEvaluator is ILoanEvaluator, OracleConsumer {
    using Math for uint256;

    /// @notice The factors a pool's positions are valued with.
    /// @dev Collateral is discounted by `collateralFactor` and borrows are inflated by `borrowFactor`, so a riskier
    ///      pool is configured with a smaller `collateralFactor` and a larger `borrowFactor`.
    /// @param collateralFactor Collateral discount factor with 4 decimals; at most `1e4`.
    /// @param borrowFactor Borrow inflation factor with 4 decimals; at least `1e4`. Wide to make it easier to force
    ///        liquidations for a deprecated pool.
    /// @param isAdded Whether the pool has been configured.
    struct PoolFactors {
        uint16 collateralFactor;
        uint32 borrowFactor;
        bool isAdded;
    }

    /// @notice Initial factor configuration for a pool.
    /// @param pool Pool to configure.
    /// @param collateralFactor Collateral discount factor with 4 decimals.
    /// @param borrowFactor Borrow inflation factor with 4 decimals.
    struct PoolFactorConfig {
        IPool pool;
        uint16 collateralFactor;
        uint32 borrowFactor;
    }

    /// @notice Role allowed to change the minimum health factor and the pool factors.
    bytes32 public constant FACTOR_CONFIG_ROLE = keccak256("FACTOR_CONFIG_ROLE");

    uint256 private _minHealthFactor; // 18dp, >= 1e18
    mapping(IPool pool => PoolFactors) private _factors;

    /// @notice Emitted when the minimum health factor is updated.
    /// @param oldMinHealthFactor The minimum health factor before the update, with 18 decimals.
    /// @param newMinHealthFactor The minimum health factor after the update, with 18 decimals.
    event MinHealthFactorUpdated(uint256 oldMinHealthFactor, uint256 newMinHealthFactor);
    /// @notice Emitted when a pool is configured for the first time.
    /// @param pool The pool configured.
    /// @param collateralFactor The pool's collateral discount factor, with 4 decimals.
    /// @param borrowFactor The pool's borrow inflation factor, with 4 decimals.
    event PoolAdded(IPool indexed pool, uint16 collateralFactor, uint32 borrowFactor);
    /// @notice Emitted when a configured pool's collateral factor is updated.
    /// @param pool The pool updated.
    /// @param oldCollateralFactor The pool's collateral factor before the update, with 4 decimals.
    /// @param newCollateralFactor The pool's collateral factor after the update, with 4 decimals.
    event CollateralFactorUpdated(IPool indexed pool, uint16 oldCollateralFactor, uint16 newCollateralFactor);
    /// @notice Emitted when a configured pool's borrow factor is updated.
    /// @param pool The pool updated.
    /// @param oldBorrowFactor The pool's borrow factor before the update, with 4 decimals.
    /// @param newBorrowFactor The pool's borrow factor after the update, with 4 decimals.
    event BorrowFactorUpdated(IPool indexed pool, uint32 oldBorrowFactor, uint32 newBorrowFactor);

    /// @notice Thrown when configuring a pool that is already configured.
    /// @param pool The pool already configured.
    error PoolAlreadyAdded(IPool pool);
    /// @notice Thrown when a pool has no factor configuration.
    /// @param pool The pool missing a configuration.
    error PoolUnknown(IPool pool);
    /// @notice Thrown when the minimum health factor would treat an undercollateralised loan as healthy.
    /// @param healthFactor The rejected minimum health factor, with 18 decimals.
    error MinHealthFactorTooLow(uint256 healthFactor);
    /// @notice Thrown when a collateral factor would value collateral above its oracle value.
    /// @param collateralFactor The rejected collateral factor, with 4 decimals.
    error CollateralFactorTooHigh(uint16 collateralFactor);
    /// @notice Thrown when a borrow factor would value a borrow below its oracle value.
    /// @param borrowFactor The rejected borrow factor, with 4 decimals.
    error BorrowFactorTooLow(uint32 borrowFactor);

    /// @notice Locks the Implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a clone with role members, oracle configuration, and initial pool factors.
    /// @dev Callable once per clone. Reverts atomically if any pool factor configuration is invalid.
    /// @param defaultAdmin Initial default admin role member.
    /// @param oracleUpdater Initial oracle updater role member.
    /// @param factorConfigurator Initial factor configurator role member.
    /// @param oracle_ Initial oracle.
    /// @param minHealthFactor_ Initial minimum health factor with 18 decimals.
    /// @param poolFactorConfigs Initial pool factor configurations.
    function initialize(
        address defaultAdmin,
        address oracleUpdater,
        address factorConfigurator,
        address oracle_,
        uint256 minHealthFactor_,
        PoolFactorConfig[] calldata poolFactorConfigs
    ) external initializer {
        __AccessControlEnumerable_init();
        _initializeOracleConsumer(oracleUpdater, oracle_);

        _updateMinHealthFactor(minHealthFactor_);

        for (uint256 i; i < poolFactorConfigs.length; ++i) {
            PoolFactorConfig calldata config = poolFactorConfigs[i];
            _addPool(config.pool, config.collateralFactor, config.borrowFactor);
        }

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        if (factorConfigurator != address(0)) _grantRole(FACTOR_CONFIG_ROLE, factorConfigurator);
    }

    /// @notice Updates the health a loan must be at to be considered healthy.
    /// @dev Raising it widens the margin between the health a loan must be left at and the health at which it becomes
    ///      liquidatable.
    /// @param newMinHealthFactor New minimum health factor with 18 decimals; at least `1e18`.
    function updateMinHealthFactor(uint256 newMinHealthFactor) external onlyRole(FACTOR_CONFIG_ROLE) {
        _updateMinHealthFactor(newMinHealthFactor);
    }

    /// @notice Configures a pool that has never been configured before.
    /// @dev A pool must be added here, and to the oracle, before it is listed in the lending core: this evaluator
    ///      reverts rather than value a pool it does not know, so a listed pool missing from here makes every
    ///      evaluation of a loan holding it revert. Since a pool can never be removed, adding it before it can hold a
    ///      position is enough to keep every loan evaluable.
    /// @param pool Pool to configure.
    /// @param collateralFactor Collateral discount factor with 4 decimals.
    /// @param borrowFactor Borrow inflation factor with 4 decimals.
    function addPool(IPool pool, uint16 collateralFactor, uint32 borrowFactor) external onlyRole(FACTOR_CONFIG_ROLE) {
        _addPool(pool, collateralFactor, borrowFactor);
    }

    /// @notice Updates a configured pool's collateral factor.
    /// @dev Lowering it discounts the pool's collateral further, which lowers the health of every loan holding it.
    /// @param pool Pool to update.
    /// @param newCollateralFactor New collateral discount factor with 4 decimals; at most `1e4`.
    function updateCollateralFactor(IPool pool, uint16 newCollateralFactor) external onlyRole(FACTOR_CONFIG_ROLE) {
        _checkCollateralFactor(newCollateralFactor);

        PoolFactors storage poolFactors = _getPoolFactorsStorage(pool);
        uint16 oldCollateralFactor = poolFactors.collateralFactor;
        poolFactors.collateralFactor = newCollateralFactor;

        emit CollateralFactorUpdated(pool, oldCollateralFactor, newCollateralFactor);
    }

    /// @notice Updates a configured pool's borrow factor.
    /// @dev Raising it inflates the pool's borrows further, which lowers the health of every loan owing it.
    /// @param pool Pool to update.
    /// @param newBorrowFactor New borrow inflation factor with 4 decimals; at least `1e4`.
    function updateBorrowFactor(IPool pool, uint32 newBorrowFactor) external onlyRole(FACTOR_CONFIG_ROLE) {
        _checkBorrowFactor(newBorrowFactor);

        PoolFactors storage poolFactors = _getPoolFactorsStorage(pool);
        uint32 oldBorrowFactor = poolFactors.borrowFactor;
        poolFactors.borrowFactor = newBorrowFactor;

        emit BorrowFactorUpdated(pool, oldBorrowFactor, newBorrowFactor);
    }

    /// @inheritdoc ILoanEvaluator
    function isLoanHealthy(ILendingCore.Loan calldata loan) external view override returns (bool) {
        return getLoanHealth(loan) >= _minHealthFactor;
    }

    /// @inheritdoc ILoanEvaluator
    /// @dev Liquidation triggers only once the loan is under-collateralised (health < 1e18), which is below the
    ///      minHealthFactor threshold used by isLoanHealthy; the gap between the two is the safety margin.
    function isLoanLiquidatable(ILendingCore.Loan calldata loan)
        external
        view
        override
        returns (bool liquidatable, uint256 health)
    {
        health = getLoanHealth(loan);
        liquidatable = health < MathUtils.ONE_18_DP;
    }

    /// @notice The health a loan must be at to be considered healthy, with 18 decimals.
    /// @return The minimum health factor.
    function minHealthFactor() external view returns (uint256) {
        return _minHealthFactor;
    }

    /// @notice The factor configuration of a pool.
    /// @dev Reverts if `pool` is not configured.
    /// @param pool The pool to query.
    /// @return The pool's factor configuration.
    function getPoolFactors(IPool pool) external view returns (PoolFactors memory) {
        return _getPoolFactorsStorage(pool);
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "FactorLoanEvaluator";
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
        return interfaceId == type(ILoanEvaluator).interfaceId || interfaceId == type(IVersioned).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @notice Whether a pool has been configured with factors this evaluator can value positions with.
    /// @param pool The pool to query.
    /// @return True if the pool is configured, false otherwise.
    function isPoolAdded(IPool pool) public view returns (bool) {
        return _factors[pool].isAdded;
    }

    /// @inheritdoc ILoanEvaluator
    /// @dev Values every leg of the loan, applying the collateral factor to collateral and the borrow factor to
    ///      borrows. Reverts if the loan holds a position in a pool this evaluator has no factors for. Every rounding
    ///      runs against the loan: collateral is valued down and borrows are valued up.
    /// @return effectiveCollateral / effectiveBorrow scaled to 18dp; type(uint256).max if no borrows.
    function getLoanHealth(ILendingCore.Loan calldata loan) public view override returns (uint256) {
        uint256 effectiveCollateral;
        uint256 collateralsLength = loan.collaterals.length;
        for (uint256 i; i < collateralsLength; ++i) {
            ILendingCore.LoanPosition calldata collateral = loan.collaterals[i];
            uint16 collateralFactor = _getPoolFactorsStorage(collateral.pool).collateralFactor;
            effectiveCollateral += _oracleValue(collateral.pool, collateral.amount, Math.Rounding.Floor)
                .mulDiv(collateralFactor, MathUtils.ONE_4_DP, Math.Rounding.Floor);
        }

        uint256 effectiveBorrow;
        uint256 borrowsLength = loan.borrows.length;
        for (uint256 i; i < borrowsLength; ++i) {
            ILendingCore.LoanPosition calldata borrow = loan.borrows[i];
            uint32 borrowFactor = _getPoolFactorsStorage(borrow.pool).borrowFactor;
            effectiveBorrow += _oracleValue(borrow.pool, borrow.amount, Math.Rounding.Ceil)
                .mulDiv(borrowFactor, MathUtils.ONE_4_DP, Math.Rounding.Ceil);
        }

        if (effectiveBorrow == 0) return type(uint256).max;
        return effectiveCollateral.mulDiv(MathUtils.ONE_18_DP, effectiveBorrow);
    }

    function _addPool(IPool pool, uint16 collateralFactor, uint32 borrowFactor) internal {
        if (isPoolAdded(pool)) revert PoolAlreadyAdded(pool);
        _checkCollateralFactor(collateralFactor);
        _checkBorrowFactor(borrowFactor);

        _factors[pool] = PoolFactors({collateralFactor: collateralFactor, borrowFactor: borrowFactor, isAdded: true});

        emit PoolAdded(pool, collateralFactor, borrowFactor);
    }

    function _updateMinHealthFactor(uint256 newMinHealthFactor) internal {
        if (newMinHealthFactor < MathUtils.ONE_18_DP) revert MinHealthFactorTooLow(newMinHealthFactor);

        uint256 oldMinHealthFactor = _minHealthFactor;
        _minHealthFactor = newMinHealthFactor;
        emit MinHealthFactorUpdated(oldMinHealthFactor, newMinHealthFactor);
    }

    function _getPoolFactorsStorage(IPool pool) internal view returns (PoolFactors storage poolFactors) {
        poolFactors = _factors[pool];
        if (!poolFactors.isAdded) revert PoolUnknown(pool);
    }

    function _checkCollateralFactor(uint16 collateralFactor) internal pure {
        if (collateralFactor > MathUtils.ONE_4_DP) revert CollateralFactorTooHigh(collateralFactor);
    }

    function _checkBorrowFactor(uint32 borrowFactor) internal pure {
        if (borrowFactor < MathUtils.ONE_4_DP) revert BorrowFactorTooLow(borrowFactor);
    }
}
