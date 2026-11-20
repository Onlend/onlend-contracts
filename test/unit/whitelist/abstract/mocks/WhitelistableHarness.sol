// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Whitelistable} from "src/whitelist/abstract/Whitelistable.sol";

contract WhitelistableHarness is Whitelistable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address whitelistConfigurator, WhitelistUpdate[] calldata updates)
        external
        initializer
    {
        __AccessControlEnumerable_init();
        _initializeWhitelistable(whitelistConfigurator, updates);

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    function checkWhitelisted(address account) external view {
        _checkWhitelisted(account);
    }
}
