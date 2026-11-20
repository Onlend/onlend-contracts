// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

/// @title Whitelistable
/// @notice Shared whitelist storage, access control, configuration, and checks for inheriting contracts.
/// @dev Provides an internal initializer for EIP-1167-compatible inheriting contracts.
abstract contract Whitelistable is AccessControlEnumerableUpgradeable {
    /// @notice Whitelist update entry.
    /// @param account Account to update.
    /// @param isWhitelisted New whitelist status.
    struct WhitelistUpdate {
        address account;
        bool isWhitelisted;
    }

    /// @notice Role allowed to update whitelist entries.
    bytes32 public constant WHITELIST_CONFIG_ROLE = keccak256("WHITELIST_CONFIG_ROLE");

    mapping(address account => bool isWhitelisted) private _whitelist;

    /// @notice Emitted when an account whitelist status is updated.
    /// @param account Account whose whitelist status was updated.
    /// @param isWhitelisted New whitelist status.
    event WhitelistUpdated(address indexed account, bool isWhitelisted);

    /// @notice Reverts when an account is not whitelisted.
    /// @param account Account that failed the whitelist check.
    error AccountNotWhitelisted(address account);

    /// @notice Initializes whitelist role members and entries for an inheriting contract.
    /// @dev Must be called from the inheriting contract's initializer, which is also responsible for initializing
    ///      access control and granting `DEFAULT_ADMIN_ROLE`.
    /// @param whitelistConfigurator Initial whitelist configurator role member.
    /// @param updates Initial whitelist updates to apply.
    function _initializeWhitelistable(address whitelistConfigurator, WhitelistUpdate[] calldata updates)
        internal
        onlyInitializing
    {
        if (whitelistConfigurator != address(0)) _grantRole(WHITELIST_CONFIG_ROLE, whitelistConfigurator);

        _setWhitelisted(updates);
    }

    /// @notice Sets whitelist status for multiple accounts.
    /// @param updates Whitelist updates to apply.
    function setWhitelisted(WhitelistUpdate[] calldata updates) external onlyRole(WHITELIST_CONFIG_ROLE) {
        _setWhitelisted(updates);
    }

    /// @notice Returns whether an account is whitelisted.
    /// @param account Account to check.
    /// @return True if the account is whitelisted.
    function isWhitelisted(address account) public view returns (bool) {
        return _whitelist[account];
    }

    /// @notice Reverts if an account is not whitelisted.
    /// @param account Account to check.
    function _checkWhitelisted(address account) internal view {
        if (!isWhitelisted(account)) revert AccountNotWhitelisted(account);
    }

    function _setWhitelisted(WhitelistUpdate[] calldata updates) private {
        for (uint256 i; i < updates.length; i++) {
            WhitelistUpdate calldata update = updates[i];
            _whitelist[update.account] = update.isWhitelisted;
            emit WhitelistUpdated(update.account, update.isWhitelisted);
        }
    }
}
