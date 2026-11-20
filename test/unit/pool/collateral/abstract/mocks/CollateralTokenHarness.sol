// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CollateralToken} from "src/pool/collateral/abstract/CollateralToken.sol";
import {ICollateralToken} from "src/pool/collateral/interfaces/ICollateralToken.sol";

contract CollateralTokenHarness is CollateralToken {
    error NotImplemented();

    constructor() {
        _disableInitializers();
    }

    function initialize(address pool_, string memory name_, string memory symbol_, uint8 decimals_)
        external
        initializer
    {
        _initializeCollateralToken(pool_, name_, symbol_, decimals_);
    }

    function contractName() external pure returns (string memory name_) {
        return "CollateralTokenHarness";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function collateralBalanceOf(address) public pure override(ICollateralToken) returns (uint256) {
        revert NotImplemented();
    }

    function totalCollateral() public pure override(ICollateralToken) returns (uint256) {
        revert NotImplemented();
    }
}
