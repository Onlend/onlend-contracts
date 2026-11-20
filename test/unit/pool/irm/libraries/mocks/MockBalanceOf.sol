// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IBalanceOf} from "src/interfaces/IBalanceOf.sol";

contract MockBalanceOf is IBalanceOf {
    error BalanceOfReverted();

    mapping(address account => uint256 balance) private _balanceOf;

    bool private _shouldRevert;
    uint256 private _returnDataLength = 32;

    function setBalance(address account, uint256 balance) external {
        _balanceOf[account] = balance;
    }

    function setShouldRevert(bool shouldRevert) external {
        _shouldRevert = shouldRevert;
    }

    function setReturnDataLength(uint256 returnDataLength) external {
        _returnDataLength = returnDataLength;
    }

    function balanceOf(address account) external view override returns (uint256 accountBalance) {
        if (_shouldRevert) revert BalanceOfReverted();

        accountBalance = _balanceOf[account];
        uint256 returnDataLength = _returnDataLength;
        if (returnDataLength != 32) {
            assembly ("memory-safe") {
                mstore(0x00, accountBalance)
                return(0x00, returnDataLength)
            }
        }
    }
}
