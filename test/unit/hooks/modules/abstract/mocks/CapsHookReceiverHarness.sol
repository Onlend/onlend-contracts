// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CapsHookReceiver} from "src/hooks/modules/abstract/CapsHookReceiver.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";

contract CapsHookReceiverHarness is CapsHookReceiver {
    uint256 private _valueResult;
    bool private _useValueResult;
    bool private _revertOnValue;

    error ValueCallReverted();

    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address capsConfigurator, PoolCapConfig[] calldata initialCaps)
        external
        initializer
    {
        __AccessControlEnumerable_init();
        _initializeCapsHookReceiver(capsConfigurator, initialCaps);

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    function setValueResult(uint256 valueResult) external {
        _valueResult = valueResult;
        _useValueResult = true;
    }

    function setRevertOnValue(bool revertOnValue) external {
        _revertOnValue = revertOnValue;
    }

    function contractName() external pure returns (string memory name_) {
        return "CapsHookReceiverHarness";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function _value(IPool, uint256 amount) internal view override returns (uint256) {
        if (_revertOnValue) revert ValueCallReverted();
        return _useValueResult ? _valueResult : amount;
    }
}
