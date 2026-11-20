// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock ERC20", "MERC20") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
