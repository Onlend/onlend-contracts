// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Standard mintable ERC-20 with configurable decimals.
contract MockToken is ERC20 {
    uint8 private immutable _DECIMALS;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _DECIMALS = decimals_;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }
}
