// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../../interfaces/IVersioned.sol";
import {IPool} from "../../../pool/interfaces/IPool.sol";
import {IHookReceiver, Phase} from "../../interfaces/IHookReceiver.sol";
import {ActionLib} from "../../lib/ActionLib.sol";

/// @title CapsHookReceiver
/// @notice Enforces configurable aggregate caps for each pool.
/// @dev Caps are checked against the pool's aggregate totals after the action, read from the pool and denominated in
///      its underlying asset. `_value()` converts them into the denomination enforced by the concrete receiver.
///      Provides an internal initializer for EIP-1167-compatible inheriting contracts.
abstract contract CapsHookReceiver is IHookReceiver, AccessControlEnumerableUpgradeable {
    /// @notice Aggregate pool exposure categories that can be capped.
    /// @dev Supply represents accounted assets, Collateral represents outstanding collateral positions, and Borrow
    ///      represents outstanding debt.
    enum CapType {
        Supply,
        Collateral,
        Borrow
    }

    /// @notice Cap configuration for one pool exposure category.
    /// @param isAdded Whether the cap exists. Kept separately because zero is a valid limit.
    /// @param limit Maximum exposure in the concrete receiver's denomination.
    struct CapConfig {
        bool isAdded;
        uint256 limit;
    }

    /// @notice Initial cap configuration for a pool exposure category.
    /// @param pool Pool whose exposure is capped.
    /// @param capType Exposure category to cap.
    /// @param limit Maximum exposure in the receiver's denomination.
    struct PoolCapConfig {
        address pool;
        CapType capType;
        uint256 limit;
    }

    /// @notice Role allowed to configure caps.
    bytes32 public constant CAPS_CONFIG_ROLE = keccak256("CAPS_CONFIG_ROLE");

    mapping(address pool => mapping(CapType capType => CapConfig config)) private _caps;

    /// @notice Emitted when a cap is added.
    /// @param pool Pool whose exposure is capped.
    /// @param capType Exposure category capped.
    /// @param limit Maximum exposure in the receiver's denomination.
    event CapAdded(address indexed pool, CapType indexed capType, uint256 limit);
    /// @notice Emitted when a cap limit is updated.
    /// @param pool Pool whose cap is updated.
    /// @param capType Exposure category updated.
    /// @param limit New maximum exposure in the receiver's denomination.
    event CapUpdated(address indexed pool, CapType indexed capType, uint256 limit);
    /// @notice Emitted when a cap is removed.
    /// @param pool Pool whose cap is removed.
    /// @param capType Exposure category removed.
    event CapRemoved(address indexed pool, CapType indexed capType);

    /// @notice Reverts when adding a cap that already exists.
    /// @param pool Pool with the existing cap.
    /// @param capType Exposure category whose cap already exists.
    error CapAlreadyAdded(address pool, CapType capType);
    /// @notice Reverts when the post-operation exposure exceeds its configured cap.
    /// @param pool Pool whose exposure exceeded the cap.
    /// @param capType Exposure category whose cap was exceeded.
    /// @param limit Configured maximum exposure.
    /// @param attemptedUsage Post-operation exposure in the receiver's denomination.
    error CapExceeded(address pool, CapType capType, uint256 limit, uint256 attemptedUsage);
    /// @notice Reverts when updating or removing a cap that does not exist.
    /// @param pool Pool without the requested cap.
    /// @param capType Exposure category whose cap does not exist.
    error CapNotFound(address pool, CapType capType);
    /// @notice Reverts when the hook action cannot increase a supported exposure category.
    /// @param action Unsupported hook action identifier.
    error UnsupportedAction(uint8 action);
    /// @notice Reverts when a hook is called before an operation.
    /// @param phase Unsupported hook phase.
    error UnsupportedPhase(Phase phase);

    /// @notice Initializes cap configuration role members for an inheriting receiver.
    /// @dev Must be called from the concrete receiver's initializer, which is also responsible for initializing access
    ///      control and granting `DEFAULT_ADMIN_ROLE`.
    /// @param capsConfigurator Initial cap configurator role member.
    /// @param initialCaps Initial pool cap configurations.
    function _initializeCapsHookReceiver(address capsConfigurator, PoolCapConfig[] calldata initialCaps)
        internal
        onlyInitializing
    {
        if (capsConfigurator != address(0)) _grantRole(CAPS_CONFIG_ROLE, capsConfigurator);

        for (uint256 i; i < initialCaps.length; ++i) {
            PoolCapConfig calldata config = initialCaps[i];
            _addCap(config.pool, config.capType, config.limit);
        }
    }

    /// @notice Adds a cap for a pool exposure category.
    /// @dev The limit may be set below the current exposure. Subsequent exposure-increasing actions revert until the
    ///      exposure falls within the limit.
    /// @param pool Pool whose exposure is capped.
    /// @param capType Exposure category to cap.
    /// @param limit Maximum exposure in the concrete receiver's denomination.
    function addCap(address pool, CapType capType, uint256 limit) external onlyRole(CAPS_CONFIG_ROLE) {
        _addCap(pool, capType, limit);
    }

    /// @notice Updates an existing cap limit.
    /// @dev The limit may be set below the current exposure. Subsequent exposure-increasing actions revert until the
    ///      exposure falls within the limit.
    /// @param pool Pool whose cap is updated.
    /// @param capType Exposure category to update.
    /// @param newLimit New maximum exposure in the concrete receiver's denomination.
    function updateCap(address pool, CapType capType, uint256 newLimit) external onlyRole(CAPS_CONFIG_ROLE) {
        _requireCapAdded(pool, capType);

        _caps[pool][capType].limit = newLimit;

        emit CapUpdated(pool, capType, newLimit);
    }

    /// @notice Removes an existing cap.
    /// @param pool Pool whose cap is removed.
    /// @param capType Exposure category to remove.
    function removeCap(address pool, CapType capType) external onlyRole(CAPS_CONFIG_ROLE) {
        _requireCapAdded(pool, capType);

        delete _caps[pool][capType];

        emit CapRemoved(pool, capType);
    }

    /// @notice Returns the cap configuration for a pool exposure category.
    /// @param pool Pool to query.
    /// @param capType Exposure category to query.
    /// @return config Cap configuration; `isAdded` is false when no cap exists.
    function getCap(address pool, CapType capType) external view returns (CapConfig memory config) {
        return _caps[pool][capType];
    }

    /// @inheritdoc IHookReceiver
    /// @dev Accepts only AFTER hooks for pool actions that can increase a supported aggregate exposure. This is
    ///      intentionally callable by anyone because it does not modify state.
    function onHook(address hookSource, Phase phase, uint8 action, bytes calldata) external view override {
        if (phase != Phase.AFTER) revert UnsupportedPhase(phase);

        if (action == ActionLib.POOL_DEPOSIT || action == ActionLib.POOL_MINT) {
            _requireWithinCap(hookSource, CapType.Supply);
        } else if (action == ActionLib.POOL_BORROW) {
            _requireWithinCap(hookSource, CapType.Borrow);
        } else if (action == ActionLib.POOL_DEPOSIT_COLLATERAL) {
            _requireWithinCap(hookSource, CapType.Supply);
            _requireWithinCap(hookSource, CapType.Collateral);
        } else {
            revert UnsupportedAction(action);
        }
    }

    /// @notice Returns whether a cap exists for a pool exposure category.
    /// @param pool Pool to query.
    /// @param capType Exposure category to query.
    /// @return True when the cap exists.
    function isCapAdded(address pool, CapType capType) public view returns (bool) {
        return _caps[pool][capType].isAdded;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return interfaceId == type(IHookReceiver).interfaceId || interfaceId == type(IVersioned).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function _addCap(address pool, CapType capType, uint256 limit) internal {
        if (isCapAdded(pool, capType)) revert CapAlreadyAdded(pool, capType);

        _caps[pool][capType] = CapConfig({isAdded: true, limit: limit});

        emit CapAdded(pool, capType, limit);
    }

    /// @notice Converts an underlying-denominated amount into the concrete receiver's cap denomination.
    /// @param pool Pool associated with the amount.
    /// @param amount Amount in the pool's underlying asset units.
    /// @return Converted value in the concrete receiver's cap denomination.
    function _value(IPool pool, uint256 amount) internal view virtual returns (uint256);

    function _requireCapAdded(address pool, CapType capType) internal view {
        if (!isCapAdded(pool, capType)) revert CapNotFound(pool, capType);
    }

    function _requireWithinCap(address pool, CapType capType) private view {
        CapConfig storage config = _caps[pool][capType];
        if (!config.isAdded) return;

        uint256 attemptedUsage = _value(IPool(pool), _total(IPool(pool), capType));
        if (attemptedUsage > config.limit) revert CapExceeded(pool, capType, config.limit, attemptedUsage);
    }

    function _total(IPool pool, CapType capType) private view returns (uint256) {
        if (capType == CapType.Supply) return pool.totalAssets();
        if (capType == CapType.Collateral) return pool.totalCollateral();
        return pool.totalDebt();
    }
}
