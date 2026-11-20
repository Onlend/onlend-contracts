// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {IPool} from "../../pool/interfaces/IPool.sol";
import {CapsHookReceiver} from "./abstract/CapsHookReceiver.sol";

/// @title NominalCapsHookReceiver
/// @notice Enforces aggregate pool caps denominated in underlying asset units.
/// @dev Applies post-action amounts without performing a valuation conversion.
///      Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract NominalCapsHookReceiver is CapsHookReceiver {
    /// @notice Locks the Implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a nominal caps receiver clone.
    /// @dev Callable once per clone.
    /// @param defaultAdmin Initial default admin role member.
    /// @param capsConfigurator Initial caps configurator role member.
    /// @param initialCaps Initial pool cap configurations.
    function initialize(address defaultAdmin, address capsConfigurator, PoolCapConfig[] calldata initialCaps)
        external
        initializer
    {
        __AccessControlEnumerable_init();
        _initializeCapsHookReceiver(capsConfigurator, initialCaps);

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /// @inheritdoc IVersioned
    function contractName() external pure override returns (string memory name_) {
        return "NominalCapsHookReceiver";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure override returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc CapsHookReceiver
    function _value(IPool, uint256 amount) internal pure override returns (uint256) {
        return amount;
    }
}
