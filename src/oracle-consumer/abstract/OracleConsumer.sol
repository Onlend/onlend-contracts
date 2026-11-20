// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IOracle} from "../../oracle/interfaces/IOracle.sol";
import {IPool} from "../../pool/interfaces/IPool.sol";

/// @title OracleConsumer
/// @notice Abstract contract that lets inheriting contracts configure an oracle and value pool amounts with it.
/// @dev Provides an internal initializer for EIP-1167-compatible inheriting contracts.
abstract contract OracleConsumer is AccessControlEnumerableUpgradeable {
    using Math for uint256;

    /// @notice Role allowed to update the oracle.
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");

    IOracle private _oracle;

    /// @notice Emitted when the oracle is updated.
    /// @param oldOracle Previous oracle.
    /// @param newOracle New oracle.
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    /// @notice Reverts when an oracle does not support `IOracle`.
    /// @param oracle Invalid oracle address.
    error InvalidOracle(address oracle);

    /// @notice Initializes OracleConsumer state for an inheriting contract.
    /// @dev Must be called from the inheriting contract's initializer, which is also responsible for initializing
    ///      access control and granting `DEFAULT_ADMIN_ROLE`.
    /// @param oracleUpdater Initial oracle updater role member.
    /// @param initialOracle Initial oracle; must support `IOracle`.
    function _initializeOracleConsumer(address oracleUpdater, address initialOracle) internal onlyInitializing {
        _updateOracle(initialOracle);

        if (oracleUpdater != address(0)) _grantRole(ORACLE_UPDATER_ROLE, oracleUpdater);
    }

    /// @notice Updates the oracle used for valuation.
    /// @dev Reverts if `newOracle` does not support `IOracle`, so the oracle can never be unset.
    /// @param newOracle New oracle.
    function updateOracle(address newOracle) external onlyRole(ORACLE_UPDATER_ROLE) {
        _updateOracle(newOracle);
    }

    /// @notice Returns the configured oracle address.
    /// @return Configured oracle address.
    function oracle() external view returns (address) {
        return address(_oracle);
    }

    function _updateOracle(address newOracle) internal {
        if (!ERC165Checker.supportsInterface(newOracle, type(IOracle).interfaceId)) revert InvalidOracle(newOracle);

        address oldOracle = address(_oracle);
        _oracle = IOracle(newOracle);
        emit OracleUpdated(oldOracle, newOracle);
    }

    /// @notice Converts an amount of a pool's underlying asset into the oracle numeraire.
    /// @dev Assumes IOracle.PriceFeed.price is the value of one whole unit of the underlying asset scaled by 18
    ///      decimals, and PriceFeed.assetDecimals is that asset's decimals, so the returned value is in the oracle
    ///      numeraire scaled by 18 decimals.
    /// @param pool Pool associated with the amount.
    /// @param amount Amount in the pool's underlying asset base units.
    /// @param rounding Rounding direction applied to the conversion.
    /// @return Converted value in the oracle numeraire, scaled by 18 decimals.
    function _oracleValue(IPool pool, uint256 amount, Math.Rounding rounding) internal view returns (uint256) {
        IOracle.PriceFeed memory priceFeed = _oracle.getPrice(pool);
        return amount.mulDiv(priceFeed.price, 10 ** priceFeed.assetDecimals, rounding);
    }
}
