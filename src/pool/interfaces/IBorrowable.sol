// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title  Borrowable Interface
/// @notice Pool whose deposited assets can be borrowed.
interface IBorrowable {
    /// @notice Brings the pool's interest rates up to date.
    function syncInterestRate() external;

    /// @notice Brings `account`'s debt in line with the interest terms that currently apply to it, and refreshes pool
    ///         interest rates.
    /// @param  account Account to synchronize.
    function syncAccount(address account) external;

    /// @notice Returns the debt token associated with this pool.
    /// @return Debt token address.
    function debtToken() external view returns (address);

    /// @notice Returns the underlying the pool holds and has not lent out.
    /// @return Current idle liquidity.
    function idleLiquidity() external view returns (uint256);

    /// @notice Returns the annualised interest rate currently earned by pool depositors, scaled to 18dp.
    /// @return Current deposit interest rate.
    function depositInterestRate() external view returns (uint256);
}
