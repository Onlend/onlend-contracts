// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {IHookReceiver, Phase} from "../interfaces/IHookReceiver.sol";

/// @title PauseHookReceiver
/// @notice Hook receiver that rejects actions paused for the hook source that fired them.
/// @dev Paused actions are kept as a bitmap per hook source, with each action identifier as its bit position. Actions
///      paused under `ALL_SOURCES` are paused for every hook source. Every action can be paused, including those that
///      reduce risk, since the issue being contained may sit in any action's path. Pausing and unpausing are separate
///      roles, so that pausing can be held by a key that responds quickly and unpausing by one with more oversight.
///      Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract PauseHookReceiver is IHookReceiver, AccessControlEnumerableUpgradeable {
    /// @notice Role allowed to pause actions.
    bytes32 public constant PAUSE_CONFIG_ROLE = keccak256("PAUSE_CONFIG_ROLE");
    /// @notice Role allowed to unpause actions.
    bytes32 public constant UNPAUSE_CONFIG_ROLE = keccak256("UNPAUSE_CONFIG_ROLE");

    /// @notice Hook source under which paused actions are paused for every hook source.
    address public constant ALL_SOURCES = address(0);

    mapping(address hookSource => uint256 pausedActions) private _pausedActions;

    /// @notice Emitted when actions are paused for a hook source.
    /// @param hookSource Hook source whose actions are paused, or `ALL_SOURCES`.
    /// @param actions Bitmap of the actions paused.
    event ActionsPaused(address indexed hookSource, uint256 actions);
    /// @notice Emitted when actions are unpaused for a hook source.
    /// @param hookSource Hook source whose actions are unpaused, or `ALL_SOURCES`.
    /// @param actions Bitmap of the actions unpaused.
    event ActionsUnpaused(address indexed hookSource, uint256 actions);

    /// @notice Reverts when a hook is called after an operation.
    /// @param phase Unsupported hook phase.
    error UnsupportedPhase(Phase phase);
    /// @notice Reverts when the hook action is paused for its hook source.
    /// @param hookSource Hook source that fired the hook.
    /// @param action Paused hook action identifier.
    error ActionPaused(address hookSource, uint8 action);

    /// @notice Locks the Implementation so it can never be initialised or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialises a clone with role members.
    /// @dev Callable once per clone.
    /// @param defaultAdmin Initial default admin role member.
    /// @param pauseConfigurators Initial pause configurator role members. Use an empty array for no initial members.
    /// @param unpauseConfigurator Initial unpause configurator role member.
    function initialize(address defaultAdmin, address[] calldata pauseConfigurators, address unpauseConfigurator)
        external
        initializer
    {
        __AccessControlEnumerable_init();

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        for (uint256 i = 0; i < pauseConfigurators.length; i++) {
            _grantRole(PAUSE_CONFIG_ROLE, pauseConfigurators[i]);
        }
        if (unpauseConfigurator != address(0)) _grantRole(UNPAUSE_CONFIG_ROLE, unpauseConfigurator);
    }

    /// @notice Pauses actions for a hook source.
    /// @dev Actions already paused stay paused, so that overlapping pauses never revert.
    /// @param hookSource Hook source whose actions to pause, or `ALL_SOURCES` to pause them for every hook source.
    /// @param actions Bitmap of the actions to pause.
    function pause(address hookSource, uint256 actions) external onlyRole(PAUSE_CONFIG_ROLE) {
        _pausedActions[hookSource] |= actions;

        emit ActionsPaused(hookSource, actions);
    }

    /// @notice Unpauses actions for a hook source.
    /// @dev Actions not paused stay unpaused, so that overlapping unpauses never revert. Unpausing under `ALL_SOURCES`
    ///      leaves actions paused under a specific hook source paused, and vice versa.
    /// @param hookSource Hook source whose actions to unpause, or `ALL_SOURCES`.
    /// @param actions Bitmap of the actions to unpause.
    function unpause(address hookSource, uint256 actions) external onlyRole(UNPAUSE_CONFIG_ROLE) {
        _pausedActions[hookSource] &= ~actions;

        emit ActionsUnpaused(hookSource, actions);
    }

    /// @inheritdoc IHookReceiver
    /// @dev Accepts only BEFORE hooks, so that a paused action reverts before it does any work. This is intentionally
    ///      callable by anyone because it does not modify state.
    function onHook(address hookSource, Phase phase, uint8 action, bytes calldata) external view override {
        if (phase != Phase.BEFORE) revert UnsupportedPhase(phase);
        if (isPaused(hookSource, action)) revert ActionPaused(hookSource, action);
    }

    /// @notice Returns the actions paused under a hook source.
    /// @dev Excludes actions paused under `ALL_SOURCES`, unless `hookSource` is `ALL_SOURCES`.
    /// @param hookSource Hook source to query, or `ALL_SOURCES`.
    /// @return Bitmap of the actions paused under `hookSource`.
    function getPausedActions(address hookSource) external view returns (uint256) {
        return _pausedActions[hookSource];
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "PauseHookReceiver";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @notice Returns whether an action is paused for a hook source, either under it or under `ALL_SOURCES`.
    /// @param hookSource Hook source to query.
    /// @param action Hook action identifier to query.
    /// @return True when the action is paused.
    function isPaused(address hookSource, uint8 action) public view returns (bool) {
        uint256 pausedActions = _pausedActions[ALL_SOURCES] | _pausedActions[hookSource];
        return (pausedActions & (uint256(1) << action)) != 0;
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
}
