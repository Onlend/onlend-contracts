// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {IOnlendFeeRegistry} from "../../pool/interfaces/IOnlendFeeRegistry.sol";
import {FeeConstants} from "../../pool/lib/FeeConstants.sol";

/// @title  OnlendFeeRegistry
/// @notice Holds the fee Onlend takes from the interest pools accrue: a default configuration for every pool, and
///         overrides for specific pools.
/// @dev    Two fees make up a configuration. The fixed fee is a share of all accrued interest, taken on top of the
///         pool's retention rate. The split fee is a share of the pool's retained interest, taken from the operator's
///         cut. A pool with no override of its own falls back to the default configuration.
///
///         Deployed once by Onlend and shared by every pool; lending apps never deploy their own.
contract OnlendFeeRegistry is IOnlendFeeRegistry, AccessControlEnumerable {
    /// @notice A fee configuration override to set for a pool.
    struct PoolFeeConfig {
        /// @notice Pool the override applies to.
        address pool;
        /// @notice Share of all accrued interest taken on top of the pool's retention, in bps.
        uint16 fixedFeeBps;
        /// @notice Share of the pool's retained interest taken from the operator's cut, in bps.
        uint16 splitFeeBps;
    }

    /// @notice A pool's own fee configuration, as stored.
    struct StoredPoolFeeConfig {
        /// @notice Whether the override applies; when unset the pool uses the default configuration.
        bool isSet;
        /// @notice Share of all accrued interest taken on top of the pool's retention, in bps.
        uint16 fixedFeeBps;
        /// @notice Share of the pool's retained interest taken from the operator's cut, in bps.
        uint16 splitFeeBps;
    }

    /// @notice Role allowed to set the default and per-pool fee configurations and the fee recipient.
    bytes32 public constant FEE_CONFIG_ROLE = keccak256("FEE_CONFIG_ROLE");

    /// @notice Default fixed fee applied to pools with no override, in bps.
    uint16 private _defaultFixedFeeBps;
    /// @notice Default split fee applied to pools with no override, in bps.
    uint16 private _defaultSplitFeeBps;
    /// @notice Per-pool fee configuration overrides, keyed by pool address.
    mapping(address pool => StoredPoolFeeConfig) private _poolFeeConfigs;
    /// @notice Account Onlend's fee shares are minted to.
    address private _feeRecipient;

    /// @notice Emitted when the default fee configuration is set.
    /// @param  fixedFeeBps New default fixed fee, in bps.
    /// @param  splitFeeBps New default split fee, in bps.
    event DefaultFeeConfigSet(uint16 fixedFeeBps, uint16 splitFeeBps);
    /// @notice Emitted when a pool's fee configuration override is set.
    /// @param  pool        Pool the override applies to.
    /// @param  fixedFeeBps New fixed fee for `pool`, in bps.
    /// @param  splitFeeBps New split fee for `pool`, in bps.
    event PoolFeeConfigSet(address indexed pool, uint16 fixedFeeBps, uint16 splitFeeBps);
    /// @notice Emitted when a pool's fee configuration override is removed.
    /// @param  pool Pool that now falls back to the default configuration.
    event PoolFeeConfigRemoved(address indexed pool);
    /// @notice Emitted when the fee recipient is set.
    /// @param  feeRecipient New fee recipient.
    event FeeRecipientSet(address indexed feeRecipient);

    /// @notice Reverts when a fixed fee exceeds 100%.
    /// @param  fixedFeeBps Invalid fixed fee, in bps.
    error FixedFeeTooHigh(uint16 fixedFeeBps);
    /// @notice Reverts when a split fee exceeds 100%.
    /// @param  splitFeeBps Invalid split fee, in bps.
    error SplitFeeTooHigh(uint16 splitFeeBps);
    /// @notice Reverts when the fee recipient is the zero address.
    error InvalidFeeRecipient();
    /// @notice Reverts when removing an override from a pool that has none.
    /// @param  pool Pool with no override.
    error PoolFeeConfigNotSet(address pool);

    /// @param  defaultAdmin       Initial default admin role member.
    /// @param  feeConfigurator    Initial fee configurator role member.
    /// @param  defaultFixedFeeBps Initial default fixed fee, in bps.
    /// @param  defaultSplitFeeBps Initial default split fee, in bps.
    /// @param  feeRecipient_      Initial fee recipient.
    constructor(
        address defaultAdmin,
        address feeConfigurator,
        uint16 defaultFixedFeeBps,
        uint16 defaultSplitFeeBps,
        address feeRecipient_
    ) {
        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        if (feeConfigurator != address(0)) _grantRole(FEE_CONFIG_ROLE, feeConfigurator);

        _setDefaultFeeConfig(defaultFixedFeeBps, defaultSplitFeeBps);
        _setFeeRecipient(feeRecipient_);
    }

    /// @notice Sets the fee configuration applied to pools with no override.
    /// @param  fixedFeeBps New default fixed fee, in bps.
    /// @param  splitFeeBps New default split fee, in bps.
    function setDefaultFeeConfig(uint16 fixedFeeBps, uint16 splitFeeBps) external onlyRole(FEE_CONFIG_ROLE) {
        _setDefaultFeeConfig(fixedFeeBps, splitFeeBps);
    }

    /// @notice Sets fee configuration overrides for pools, replacing any they already have.
    /// @dev    Reverts the whole batch if any fee is invalid. A pool listed more than once takes its last entry.
    /// @param  configs Pool fee configuration overrides to set.
    function setPoolFeeConfigs(PoolFeeConfig[] calldata configs) external onlyRole(FEE_CONFIG_ROLE) {
        for (uint256 i; i < configs.length; i++) {
            PoolFeeConfig calldata config = configs[i];
            _validateFeeConfig(config.fixedFeeBps, config.splitFeeBps);

            _poolFeeConfigs[config.pool] =
                StoredPoolFeeConfig({isSet: true, fixedFeeBps: config.fixedFeeBps, splitFeeBps: config.splitFeeBps});

            emit PoolFeeConfigSet(config.pool, config.fixedFeeBps, config.splitFeeBps);
        }
    }

    /// @notice Removes pools' fee configuration overrides so they fall back to the default configuration.
    /// @dev    Reverts the whole batch if any pool has no override, including a pool listed more than once.
    /// @param  pools Pools to remove the override from.
    function removePoolFeeConfigs(address[] calldata pools) external onlyRole(FEE_CONFIG_ROLE) {
        for (uint256 i; i < pools.length; i++) {
            address pool = pools[i];
            if (!_poolFeeConfigs[pool].isSet) revert PoolFeeConfigNotSet(pool);

            delete _poolFeeConfigs[pool];

            emit PoolFeeConfigRemoved(pool);
        }
    }

    /// @notice Sets the account Onlend's fee shares are minted to.
    /// @param  feeRecipient_ New fee recipient.
    function setFeeRecipient(address feeRecipient_) external onlyRole(FEE_CONFIG_ROLE) {
        _setFeeRecipient(feeRecipient_);
    }

    /// @inheritdoc IOnlendFeeRegistry
    /// @dev    A pool with no override of its own falls back to the default configuration.
    function feeConfig(address pool)
        external
        view
        override(IOnlendFeeRegistry)
        returns (uint16 fixedFeeBps, uint16 splitFeeBps)
    {
        StoredPoolFeeConfig storage poolConfig = _poolFeeConfigs[pool];
        if (poolConfig.isSet) return (poolConfig.fixedFeeBps, poolConfig.splitFeeBps);
        return (_defaultFixedFeeBps, _defaultSplitFeeBps);
    }

    /// @notice Returns the fee configuration applied to pools with no override.
    /// @return fixedFeeBps Default fixed fee, in bps.
    /// @return splitFeeBps Default split fee, in bps.
    function defaultFeeConfig() external view returns (uint16 fixedFeeBps, uint16 splitFeeBps) {
        return (_defaultFixedFeeBps, _defaultSplitFeeBps);
    }

    /// @notice Returns whether a pool has a fee configuration override.
    /// @param  pool Pool to query.
    /// @return True if `pool` has an override.
    function hasPoolFeeConfig(address pool) external view returns (bool) {
        return _poolFeeConfigs[pool].isSet;
    }

    /// @inheritdoc IOnlendFeeRegistry
    function feeRecipient() external view override(IOnlendFeeRegistry) returns (address) {
        return _feeRecipient;
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "OnlendFeeRegistry";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlEnumerable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IOnlendFeeRegistry).interfaceId || interfaceId == type(IVersioned).interfaceId
            || AccessControlEnumerable.supportsInterface(interfaceId);
    }

    function _setDefaultFeeConfig(uint16 fixedFeeBps, uint16 splitFeeBps) internal {
        _validateFeeConfig(fixedFeeBps, splitFeeBps);

        _defaultFixedFeeBps = fixedFeeBps;
        _defaultSplitFeeBps = splitFeeBps;

        emit DefaultFeeConfigSet(fixedFeeBps, splitFeeBps);
    }

    function _setFeeRecipient(address feeRecipient_) internal {
        if (feeRecipient_ == address(0)) revert InvalidFeeRecipient();

        _feeRecipient = feeRecipient_;

        emit FeeRecipientSet(feeRecipient_);
    }

    function _validateFeeConfig(uint16 fixedFeeBps, uint16 splitFeeBps) internal pure {
        if (fixedFeeBps > FeeConstants.MAX_FEE_BPS) revert FixedFeeTooHigh(fixedFeeBps);
        if (splitFeeBps > FeeConstants.MAX_FEE_BPS) revert SplitFeeTooHigh(splitFeeBps);
    }
}
