// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {FlashLendable} from "src/pool/abstract/FlashLendable.sol";

contract FlashLendableHarness is FlashLendable {
    address private _token;

    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address flashLoanConfigurator, bool initialFlashLoansEnabled)
        external
        initializer
    {
        __AccessControlEnumerable_init();
        _initializeFlashLendable(flashLoanConfigurator, initialFlashLoansEnabled);

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    function setFlashLoanToken(address token) external {
        _token = token;
    }

    function _flashLoanToken() internal view override returns (address) {
        return _token;
    }
}
