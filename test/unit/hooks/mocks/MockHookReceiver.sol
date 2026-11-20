// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IHookReceiver, Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

contract MockHookReceiver is IHookReceiver {
    uint256 public calls;
    address public lastHookSource;
    Phase public lastPhase;
    uint8 public lastAction;
    bytes public lastData;
    bool public shouldRevert;

    event HookCalled(address hookSource, Phase phase, uint8 action, bytes data);

    error HookReceiverReverted();

    function setShouldRevert(bool shouldRevert_) external {
        shouldRevert = shouldRevert_;
    }

    function onHook(address hookSource, Phase phase, uint8 action, bytes calldata data) external {
        if (shouldRevert) revert HookReceiverReverted();

        calls++;
        lastHookSource = hookSource;
        lastPhase = phase;
        lastAction = action;
        lastData = data;

        emit HookCalled(hookSource, phase, action, data);
    }

    function contractName() external pure returns (string memory name_) {
        return "MockHookReceiver";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IHookReceiver).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
