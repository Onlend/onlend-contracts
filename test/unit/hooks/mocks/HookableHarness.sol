// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Hookable} from "src/hooks/abstract/Hookable.sol";
import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";

contract HookableHarness is Hookable {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        address hookUpdater,
        address initialHookReceiver,
        uint256 initialBeforeHookBitmap,
        uint256 initialAfterHookBitmap
    ) external initializer {
        __AccessControlEnumerable_init();
        _initializeHookable(hookUpdater, initialHookReceiver, initialBeforeHookBitmap, initialAfterHookBitmap);

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    function fireHook(Phase phase, uint8 action, bytes memory data) external {
        _fireHook(phase, action, data);
    }
}
