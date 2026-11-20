// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IHookReceiver, Phase} from "../interfaces/IHookReceiver.sol";

/// @title Hookable
/// @notice Abstract contract that lets inheriting contracts configure and fire hooks.
/// @dev Provides an internal initializer for EIP-1167-compatible inheriting contracts.
abstract contract Hookable is AccessControlEnumerableUpgradeable {
    /// @notice Role allowed to configure hook receiver and hook bitmaps.
    bytes32 public constant HOOK_UPDATER_ROLE = keccak256("HOOK_UPDATER_ROLE");

    IHookReceiver private _hookReceiver;
    uint256 private _beforeHookBitmap;
    uint256 private _afterHookBitmap;

    /// @notice Emitted when the hook receiver is updated.
    /// @param oldHookReceiver Previous hook receiver address.
    /// @param newHookReceiver New hook receiver address.
    event HookReceiverSet(address indexed oldHookReceiver, address indexed newHookReceiver);
    /// @notice Emitted when hook bitmaps are updated.
    /// @param oldBeforeBitmap Previous before-hook bitmap.
    /// @param oldAfterBitmap Previous after-hook bitmap.
    /// @param newBeforeBitmap New before-hook bitmap.
    /// @param newAfterBitmap New after-hook bitmap.
    event HookBitmapsSet(
        uint256 oldBeforeBitmap, uint256 oldAfterBitmap, uint256 newBeforeBitmap, uint256 newAfterBitmap
    );

    /// @notice Reverts when a hook receiver does not support `IHookReceiver`.
    /// @param hookReceiver Invalid hook receiver address.
    error InvalidHookReceiver(address hookReceiver);

    /// @notice Initializes Hookable state for an inheriting contract.
    /// @dev Must be called from the inheriting contract's initializer, which is also responsible for initializing
    ///      access control and granting `DEFAULT_ADMIN_ROLE`.
    /// @param hookUpdater Initial hook updater role member.
    /// @param initialHookReceiver Initial hook receiver, or the zero address to disable hooks.
    /// @param initialBeforeHookBitmap Initial before-hook bitmap.
    /// @param initialAfterHookBitmap Initial after-hook bitmap.
    function _initializeHookable(
        address hookUpdater,
        address initialHookReceiver,
        uint256 initialBeforeHookBitmap,
        uint256 initialAfterHookBitmap
    ) internal onlyInitializing {
        if (hookUpdater != address(0)) _grantRole(HOOK_UPDATER_ROLE, hookUpdater);

        _setHookReceiver(initialHookReceiver);
        _setHookBitmaps(initialBeforeHookBitmap, initialAfterHookBitmap);
    }

    /// @notice Sets the hook receiver.
    /// @dev Set to the zero address to disable hook calls.
    /// @param newHookReceiver New hook receiver.
    function setHookReceiver(address newHookReceiver) external onlyRole(HOOK_UPDATER_ROLE) {
        _setHookReceiver(newHookReceiver);
    }

    /// @notice Sets before-hook and after-hook bitmaps.
    /// @dev A hook fires when the bit for its action identifier is enabled.
    /// @param beforeBitmap Bitmap for before hooks.
    /// @param afterBitmap Bitmap for after hooks.
    function setHookBitmaps(uint256 beforeBitmap, uint256 afterBitmap) external onlyRole(HOOK_UPDATER_ROLE) {
        _setHookBitmaps(beforeBitmap, afterBitmap);
    }

    /// @notice Returns the configured hook receiver address.
    /// @return Configured hook receiver address.
    function hookReceiver() external view returns (address) {
        return address(_hookReceiver);
    }

    /// @notice Returns the configured before-hook and after-hook bitmaps.
    /// @return beforeBitmap Bitmap for before hooks.
    /// @return afterBitmap Bitmap for after hooks.
    function hookBitmaps() external view returns (uint256 beforeBitmap, uint256 afterBitmap) {
        return (_beforeHookBitmap, _afterHookBitmap);
    }

    function _setHookReceiver(address newHookReceiver) internal {
        if (
            newHookReceiver != address(0)
                && !ERC165Checker.supportsInterface(newHookReceiver, type(IHookReceiver).interfaceId)
        ) revert InvalidHookReceiver(newHookReceiver);

        address oldHookReceiver = address(_hookReceiver);
        _hookReceiver = IHookReceiver(newHookReceiver);
        emit HookReceiverSet(oldHookReceiver, newHookReceiver);
    }

    function _setHookBitmaps(uint256 beforeBitmap, uint256 afterBitmap) internal {
        uint256 oldBeforeBitmap = _beforeHookBitmap;
        uint256 oldAfterBitmap = _afterHookBitmap;

        _beforeHookBitmap = beforeBitmap;
        _afterHookBitmap = afterBitmap;
        emit HookBitmapsSet(oldBeforeBitmap, oldAfterBitmap, beforeBitmap, afterBitmap);
    }

    /// @notice Fires a hook when a receiver is configured and the action bit is enabled.
    /// @param phase Hook execution phase.
    /// @param action Hook action identifier.
    /// @param data Encoded hook payload.
    function _fireHook(Phase phase, uint8 action, bytes memory data) internal {
        if (address(_hookReceiver) == address(0)) return;

        uint256 bitmap = phase == Phase.BEFORE ? _beforeHookBitmap : _afterHookBitmap;
        if ((bitmap & (uint256(1) << action)) == 0) return;

        _hookReceiver.onHook(address(this), phase, action, data);
    }
}
