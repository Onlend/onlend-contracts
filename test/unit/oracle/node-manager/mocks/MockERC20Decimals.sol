// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @dev Exposes only the ERC-20 `decimals()` read by the VAULT_SHARE_PRICE node from a vault's asset.
contract MockERC20Decimals {
    bool public shouldRevertOnDecimals;

    uint8 private _decimals;

    error DecimalsReverted();

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function setShouldRevertOnDecimals(bool value) external {
        shouldRevertOnDecimals = value;
    }

    function decimals() external view returns (uint8) {
        if (shouldRevertOnDecimals) revert DecimalsReverted();
        return _decimals;
    }
}
