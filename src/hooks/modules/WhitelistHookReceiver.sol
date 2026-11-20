// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {IHookReceiver, Phase} from "../interfaces/IHookReceiver.sol";
import {ActionLib} from "../lib/ActionLib.sol";
import {Whitelistable} from "../../whitelist/abstract/Whitelistable.sol";

/// @title WhitelistHookReceiver
/// @notice Hook receiver that only lets whitelisted accounts take on a position in a pool.
/// @dev Each supported action checks the party that takes on a position: the account that deposits, mints, deposits
///      collateral or borrows, the recipient of a share transfer, and the receiver of seized collateral. Funds leaving
///      a pool are not checked, since a whitelisted account could forward them on regardless. Actions that only reduce
///      risk or maintain a pool take on no position, so are unsupported and an account removed from the whitelist can
///      still repay.
///
///      Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract WhitelistHookReceiver is IHookReceiver, Whitelistable {
    uint256 private constant ABI_WORD_SIZE = 32;
    uint256 private constant ACCOUNT_POSITION = 0;
    uint256 private constant COUNTERPARTY_POSITION = 1;

    /// @notice Reverts when hook data is too short to contain the account to check.
    error InvalidHookData();
    /// @notice Reverts when a hook is called after an operation.
    /// @param phase Unsupported hook phase.
    error UnsupportedPhase(Phase phase);
    /// @notice Reverts when the hook action is not one this receiver checks.
    /// @param action Unsupported hook action identifier.
    error UnsupportedAction(uint8 action);

    /// @notice Locks the Implementation so it can never be initialised or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialises a clone with role members and whitelisted accounts.
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

    /// @inheritdoc IHookReceiver
    /// @dev Accepts only BEFORE hooks, so that an action by an account not whitelisted reverts before it does any work.
    ///      This is intentionally callable by anyone because it does not modify state.
    function onHook(address, Phase phase, uint8 action, bytes calldata data) external view override {
        if (phase != Phase.BEFORE) revert UnsupportedPhase(phase);

        if (
            action == ActionLib.LC_DEPOSIT_COLLATERAL || action == ActionLib.LC_BORROW
                || action == ActionLib.POOL_DEPOSIT_COLLATERAL || action == ActionLib.POOL_BORROW
                || action == ActionLib.POOL_DEPOSIT || action == ActionLib.POOL_MINT
        ) {
            _checkWhitelistedAt(data, ACCOUNT_POSITION);
        } else if (
            action == ActionLib.LC_LIQUIDATE || action == ActionLib.POOL_SEIZE_COLLATERAL
                || action == ActionLib.POOL_TRANSFER
        ) {
            _checkWhitelistedAt(data, COUNTERPARTY_POSITION);
        } else {
            revert UnsupportedAction(action);
        }
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "WhitelistHookReceiver";
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
        return interfaceId == type(IHookReceiver).interfaceId || interfaceId == type(IVersioned).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function _checkWhitelistedAt(bytes calldata data, uint256 position) private view {
        uint256 start = position * ABI_WORD_SIZE;
        uint256 end = start + ABI_WORD_SIZE;
        if (data.length < end) revert InvalidHookData();

        _checkWhitelisted(abi.decode(data[start:end], (address)));
    }
}
