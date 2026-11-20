// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ICollateralToken} from "../collateral/interfaces/ICollateralToken.sol";
import {ICollateralisable} from "../interfaces/ICollateralisable.sol";
import {BasePool} from "./BasePool.sol";

/// @title Collateralisable
/// @notice Gives a pool the ability to hold positions that back a loan. See {ICollateralisable}.
/// @dev Owns the collateral token dependency and reports what it represents. The collateral entry points and their
///      hooks live in `BasePool`; an inheriting pool supplies the accounting and asset movement behind them, which
///      differs by how the pool represents a position.
abstract contract Collateralisable is ICollateralisable, BasePool {
    /// @notice Collateral token representing the positions this pool holds.
    ICollateralToken internal _collateralToken;

    /// @notice Reverts when collateral arguments are invalid for the concrete pool.
    error InvalidCollateralArgs();

    /// @notice Reverts when a collateral token does not support `ICollateralToken`.
    /// @param collateralToken Invalid collateral token address.
    error InvalidCollateralToken(address collateralToken);

    /// @notice Initializes the collateral token dependency for an inheriting pool.
    /// @dev Must be called from the concrete pool's initializer. Grants no roles.
    /// @param collateralToken_ Collateral token associated with this pool.
    /// @param assetDecimals Decimals the collateral token must report, being those of the pool's underlying asset.
    function _initializeCollateralisable(address collateralToken_, uint8 assetDecimals) internal onlyInitializing {
        _validateCollateralToken(collateralToken_);
        _validateTokenDecimals(collateralToken_, assetDecimals);

        _collateralToken = ICollateralToken(collateralToken_);
    }

    /// @inheritdoc ICollateralisable
    function collateralToken() external view returns (address) {
        return address(_collateralToken);
    }

    /// @inheritdoc BasePool
    function totalCollateral() public view virtual override(BasePool) returns (uint256) {
        return _collateralToken.totalCollateral();
    }

    /// @inheritdoc BasePool
    function collateralOf(address account) public view virtual override(BasePool) returns (uint256) {
        return _collateralToken.collateralBalanceOf(account);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ICollateralisable).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Validates a collateral token dependency.
    /// @param collateralToken_ Collateral token dependency to validate.
    function _validateCollateralToken(address collateralToken_) internal view {
        if (!ERC165Checker.supportsInterface(collateralToken_, type(ICollateralToken).interfaceId)) {
            revert InvalidCollateralToken(collateralToken_);
        }
    }
}
