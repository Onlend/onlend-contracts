// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @dev Token stand-in reporting the decimals it was constructed with. `Pool` only reads `decimals()` off the tokens it
///      denominates against, so decimals validation is exercised without pulling in a full ERC-20.
contract MockDecimalsToken {
    uint8 public decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}
