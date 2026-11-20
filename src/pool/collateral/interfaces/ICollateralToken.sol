// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../../interfaces/IVersioned.sol";

/// @title  ICollateralToken
/// @notice Non-transferable ERC-20 representing an account's collateral position in a pool.
interface ICollateralToken is IERC20, IERC165, IVersioned {
    /// @notice Mints collateral tokens to `account`.
    /// @param  account Account to receive the minted tokens
    /// @param  amount  Amount to mint
    function mint(address account, uint256 amount) external;

    /// @notice Burns collateral tokens from `account`.
    /// @param  account Account to burn tokens from
    /// @param  amount  Amount to burn
    function burn(address account, uint256 amount) external;

    /// @notice Pool contract this collateral token belongs to.
    /// @return Pool address
    function pool() external view returns (address);

    /// @notice Collateral balance of `account`, denominated in the underlying asset.
    /// @param  account Account to query
    /// @return Collateral balance in underlying asset units
    function collateralBalanceOf(address account) external view returns (uint256);

    /// @notice Total collateral represented by the token supply, denominated in the underlying asset.
    /// @return Total collateral in underlying asset units
    function totalCollateral() external view returns (uint256);
}
