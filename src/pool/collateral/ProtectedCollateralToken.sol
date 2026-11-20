// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {CollateralToken} from "./abstract/CollateralToken.sol";
import {ICollateralToken} from "./interfaces/ICollateralToken.sol";

/// @title  ProtectedCollateralToken
/// @notice Collateral token for non-borrowable pool.
/// @dev    `balanceOf` holds asset amounts 1:1; `collateralBalanceOf` is a direct passthrough.
///         Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract ProtectedCollateralToken is CollateralToken {
    /// @notice Locks the Implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a protected collateral token clone.
    /// @dev Callable once per clone.
    /// @param pool_ Pool contract authorised to `mint`/`burn`.
    /// @param name_ Collateral token name.
    /// @param symbol_ Collateral token symbol.
    /// @param decimals_ Decimals to report, matching the underlying asset.
    function initialize(address pool_, string calldata name_, string calldata symbol_, uint8 decimals_)
        external
        initializer
    {
        _initializeCollateralToken(pool_, name_, symbol_, decimals_);
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "ProtectedCollateralToken";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc ICollateralToken
    function collateralBalanceOf(address account) public view override(ICollateralToken) returns (uint256) {
        return balanceOf(account);
    }

    /// @inheritdoc ICollateralToken
    function totalCollateral() public view override(ICollateralToken) returns (uint256) {
        return totalSupply();
    }
}
