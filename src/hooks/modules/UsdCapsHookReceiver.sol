// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {OracleConsumer} from "../../oracle-consumer/abstract/OracleConsumer.sol";
import {IPool} from "../../pool/interfaces/IPool.sol";
import {CapsHookReceiver} from "./abstract/CapsHookReceiver.sol";

/// @title UsdCapsHookReceiver
/// @notice Enforces aggregate pool caps denominated in USD.
/// @dev Converts post-action underlying amounts using the configured oracle and rounds values up.
///      Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract UsdCapsHookReceiver is CapsHookReceiver, OracleConsumer {
    /// @notice Locks the Implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a USD caps receiver clone.
    /// @dev Callable once per clone.
    /// @param defaultAdmin Initial default admin role member.
    /// @param capsConfigurator Initial caps configurator role member.
    /// @param oracleUpdater Initial oracle updater role member.
    /// @param oracle_ Initial oracle.
    /// @param initialCaps Initial pool cap configurations.
    function initialize(
        address defaultAdmin,
        address capsConfigurator,
        address oracleUpdater,
        address oracle_,
        PoolCapConfig[] calldata initialCaps
    ) external initializer {
        __AccessControlEnumerable_init();
        _initializeCapsHookReceiver(capsConfigurator, initialCaps);
        _initializeOracleConsumer(oracleUpdater, oracle_);

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /// @inheritdoc IVersioned
    function contractName() external pure override returns (string memory name_) {
        return "UsdCapsHookReceiver";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure override returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(CapsHookReceiver, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc CapsHookReceiver
    function _value(IPool pool, uint256 amount) internal view override returns (uint256) {
        return _oracleValue(pool, amount, Math.Rounding.Ceil);
    }
}
