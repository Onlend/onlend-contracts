// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IVersioned} from "../interfaces/IVersioned.sol";
import {IHookReceiver, Phase} from "./interfaces/IHookReceiver.sol";

/// @title MultiHookReceiver
/// @notice Dispatches hook callbacks to multiple hook receivers for each phase and action.
/// @dev Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract MultiHookReceiver is IHookReceiver, AccessControlEnumerableUpgradeable {
    /// @notice Hook receiver configuration for a phase and action.
    /// @param phase Hook execution phase.
    /// @param action Hook action identifier.
    /// @param hookReceivers New hook receiver list, replacing any previously configured receivers.
    struct HookReceiverConfig {
        Phase phase;
        uint8 action;
        address[] hookReceivers;
    }

    /// @notice Role allowed to update configured hook receivers.
    bytes32 public constant HOOK_RECEIVERS_UPDATER_ROLE = keccak256("HOOK_RECEIVERS_UPDATER_ROLE");
    /// @notice Role allowed to call hooks through this receiver.
    bytes32 public constant HOOK_CALLER_ROLE = keccak256("HOOK_CALLER_ROLE");

    mapping(Phase phase => mapping(uint8 action => address[] hookReceivers)) private _hookReceivers;

    /// @notice Emitted when hook receivers are updated for a phase and action.
    /// @param phase Hook execution phase.
    /// @param action Hook action identifier.
    /// @param hookReceivers New hook receiver list.
    event HookReceiversSet(Phase indexed phase, uint8 indexed action, address[] hookReceivers);

    /// @notice Reverts when a hook receiver does not support `IHookReceiver`.
    /// @param hookReceiver Invalid hook receiver address.
    error InvalidHookReceiver(address hookReceiver);

    /// @notice Locks the Implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a clone with role members and hook receiver configs.
    /// @dev Callable once per clone.
    /// @param defaultAdmin Initial default admin role member.
    /// @param hookReceiversUpdater Initial hook receivers updater role member.
    /// @param hookCallers Initial hook caller role members. Use an empty array for no initial members.
    /// @param configs Initial hook receiver configs to apply.
    function initialize(
        address defaultAdmin,
        address hookReceiversUpdater,
        address[] calldata hookCallers,
        HookReceiverConfig[] calldata configs
    ) external initializer {
        __AccessControlEnumerable_init();

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        if (hookReceiversUpdater != address(0)) _grantRole(HOOK_RECEIVERS_UPDATER_ROLE, hookReceiversUpdater);
        for (uint256 i = 0; i < hookCallers.length; i++) {
            _grantRole(HOOK_CALLER_ROLE, hookCallers[i]);
        }

        _setHookReceivers(configs);
    }

    /// @notice Sets hook receivers for multiple phase and action pairs.
    /// @dev Replaces the full receiver list for each config. Use an empty array to clear configured receivers. Reverts
    ///      atomically if any config contains an invalid receiver. If multiple configs target the same phase and
    ///      action, the last config takes effect. Does not enforce receiver count, receiver gas cost, or duplicate
    ///      receivers, and does not detect cycles. The hook receivers updater is responsible for configuring receiver
    ///      lists that keep hook execution within gas limits and contain no cycles.
    /// @param configs Hook receiver configs to apply.
    function setHookReceivers(HookReceiverConfig[] calldata configs) external onlyRole(HOOK_RECEIVERS_UPDATER_ROLE) {
        _setHookReceivers(configs);
    }

    /// @inheritdoc IHookReceiver
    /// @dev Calls configured receivers in order. If any receiver reverts, the full hook call reverts. Callers with
    ///      `HOOK_CALLER_ROLE` are trusted to provide the correct `hookSource`, which is forwarded unchanged and may
    ///      differ from `msg.sender` to support nested `MultiHookReceiver` calls. Gas usage grows with the number and
    ///      complexity of configured receivers.
    function onHook(address hookSource, Phase phase, uint8 action, bytes calldata data)
        external
        override
        onlyRole(HOOK_CALLER_ROLE)
    {
        address[] memory hookReceivers = _hookReceivers[phase][action];

        for (uint256 i = 0; i < hookReceivers.length; i++) {
            IHookReceiver(hookReceivers[i]).onHook(hookSource, phase, action, data);
        }
    }

    /// @notice Returns hook receivers configured for a phase and action.
    /// @param phase Hook execution phase.
    /// @param action Hook action identifier.
    /// @return Hook receiver list.
    function getHookReceivers(Phase phase, uint8 action) external view returns (address[] memory) {
        return _hookReceivers[phase][action];
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "MultiHookReceiver";
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

    function _setHookReceivers(HookReceiverConfig[] calldata configs) private {
        for (uint256 i = 0; i < configs.length; i++) {
            Phase phase = configs[i].phase;
            uint8 action = configs[i].action;
            address[] calldata hookReceivers = configs[i].hookReceivers;

            for (uint256 j = 0; j < hookReceivers.length; j++) {
                if (!ERC165Checker.supportsInterface(hookReceivers[j], type(IHookReceiver).interfaceId)) {
                    revert InvalidHookReceiver(hookReceivers[j]);
                }
            }

            _hookReceivers[phase][action] = hookReceivers;
            emit HookReceiversSet(phase, action, hookReceivers);
        }
    }
}
