// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";

/// @notice Hook execution phase.
enum Phase {
    BEFORE,
    AFTER
}

/// @title HookReceiver Interface
/// @notice Receives hook callbacks emitted by hookable contracts.
interface IHookReceiver is IERC165, IVersioned {
    /// @notice Handles a hook callback.
    /// @dev In permissionless implementations, `hookSource` is caller-provided and must not be trusted without
    ///      validation.
    /// @param hookSource Contract that originated the hook.
    /// @param phase Hook execution phase.
    /// @param action Hook action identifier.
    /// @param data Encoded hook payload.
    function onHook(address hookSource, Phase phase, uint8 action, bytes calldata data) external;
}
