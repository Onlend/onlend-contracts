// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../../interfaces/IVersioned.sol";

/// @title  IDebtToken
/// @notice Non-transferable ERC-20 representing an account's debt position in a pool.
/// @dev    Every implementation must report `balanceOf` and `totalSupply` current as of this block, including interest
///         not yet accrued.
interface IDebtToken is IERC20, IERC165, IVersioned {
    /// @notice Accrues interest up to the current timestamp.
    /// @return accrued  Interest accrued over the elapsed period, in underlying assets.
    /// @return retained Part of `accrued` retained under the retention rate, in underlying assets.
    function accrueInterest() external returns (uint256 accrued, uint256 retained);

    /// @notice Brings `account`'s debt in line with the interest terms that currently apply to it.
    /// @param  account Account to synchronize
    function syncAccount(address account) external;

    /// @notice Recomputes borrow and retention rates.
    /// @param  idleLiquidity Current idle liquidity in the pool
    function updateBorrowRates(uint256 idleLiquidity) external;

    /// @notice Increases `account`'s debt by `amount`.
    /// @param  account Account to receive minted debt
    /// @param  amount  Amount to mint
    function mint(address account, uint256 amount) external;

    /// @notice Decreases `account`'s debt by `amount`.
    /// @param  account Account to burn debt from
    /// @param  amount  Amount to burn
    function burn(address account, uint256 amount) external;

    /// @notice Pool contract this debt token belongs to.
    /// @return Pool address
    function pool() external view returns (address);

    /// @notice Returns the interest accrued since the last accrual and not yet handed to the pool.
    /// @return accrued  Interest `accrueInterest` would return if called now, in underlying assets.
    /// @return retained Retention `accrueInterest` would return if called now, in underlying assets.
    function pendingInterest() external view returns (uint256 accrued, uint256 retained);

    /// @notice Returns the annualised interest the outstanding debt currently generates.
    /// @dev    Priced at the stored borrow and retention rates, which is what interest accrues at until the rates are
    ///         next recomputed, against debt brought up to the current block.
    /// @return interest Borrow interest flow — outstanding debt scaled by the borrow rate.
    /// @return retained Part of `interest` retained under the retention rate.
    function annualInterest() external view returns (uint256 interest, uint256 retained);
}
