// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {Whitelistable} from "../../../../whitelist/abstract/Whitelistable.sol";
import {IVersioned} from "../../../../interfaces/IVersioned.sol";
import {IConditionModule} from "../../interfaces/IConditionModule.sol";
import {IValidatableModule} from "../../interfaces/IValidatableModule.sol";

/// @title Whitelist Condition
/// @notice External IRM condition that applies only to whitelisted accounts.
/// @dev Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract WhitelistCondition is IConditionModule, Whitelistable {
    /// @notice Locks the implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a clone with role members and whitelisted accounts.
    /// @dev Callable once per clone.
    /// @param defaultAdmin Initial default admin role member.
    /// @param whitelistConfigurator Initial whitelist configurator role member.
    /// @param updates Initial whitelist updates to apply.
    function initialize(address defaultAdmin, address whitelistConfigurator, WhitelistUpdate[] calldata updates)
        external
        initializer
    {
        __AccessControlEnumerable_init();
        _initializeWhitelistable(whitelistConfigurator, updates);

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /// @inheritdoc IConditionModule
    /// @dev Encoded parameters are ignored because whitelist membership is stored by this contract.
    function isApplicable(bytes calldata, address account) external view override returns (bool) {
        return isWhitelisted(account);
    }

    /// @inheritdoc IValidatableModule
    /// @dev `params` must be empty because whitelist membership is stored by this contract.
    function isValid(bytes calldata params) external pure override returns (bool) {
        return params.length == 0;
    }

    /// @inheritdoc IVersioned
    function contractName() external pure override returns (string memory name_) {
        return "WhitelistCondition";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure override returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IERC165, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return interfaceId == type(IConditionModule).interfaceId || interfaceId == type(IValidatableModule).interfaceId
            || interfaceId == type(IVersioned).interfaceId || super.supportsInterface(interfaceId);
    }
}
