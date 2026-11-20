// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {BasePool} from "src/pool/abstract/BasePool.sol";

contract BasePoolNoCapabilitiesHarness is BasePool {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        address hookUpdater,
        address flashLoanConfigurator,
        address initialHookReceiver,
        uint256 initialBeforeHookBitmap,
        uint256 initialAfterHookBitmap,
        address lendingCore_,
        bool initialFlashLoansEnabled
    ) external initializer {
        __AccessControlEnumerable_init();
        _initializePool(
            hookUpdater,
            flashLoanConfigurator,
            initialHookReceiver,
            initialBeforeHookBitmap,
            initialAfterHookBitmap,
            lendingCore_,
            initialFlashLoansEnabled
        );

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    function contractName() external pure returns (string memory name_) {
        return "BasePoolNoCapabilitiesHarness";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function asset() public pure override(BasePool) returns (address) {
        return address(0);
    }

    function totalAssets() public pure override(BasePool) returns (uint256) {
        return 0;
    }
}
