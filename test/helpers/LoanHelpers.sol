// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";

/// @dev Reusable builders for constructing `ILendingCore.Loan` structs in tests.
library LoanHelpers {
    /// @dev Builds an empty loan with no collateral and no borrow.
    function emptyLoan() internal pure returns (ILendingCore.Loan memory loan) {
        loan.account = address(0);
        loan.collaterals = noPositions();
        loan.borrows = noPositions();
    }

    /// @dev Builds a loan with a single collateral and no borrow.
    function loanWithSingleCollateral(address account, IPool pool, uint256 collateralAmount)
        internal
        pure
        returns (ILendingCore.Loan memory loan)
    {
        loan.account = account;
        loan.collaterals = positions(pool, collateralAmount);
        loan.borrows = noPositions();
    }

    /// @dev Builds a loan with no collateral and a single borrow.
    function loanWithSingleBorrow(address account, IPool pool, uint256 borrowAmount)
        internal
        pure
        returns (ILendingCore.Loan memory loan)
    {
        loan.account = account;
        loan.collaterals = noPositions();
        loan.borrows = positions(pool, borrowAmount);
    }

    /// @dev Builds an empty position array, for a loan holding nothing on that side.
    function noPositions() internal pure returns (ILendingCore.LoanPosition[] memory result) {
        result = new ILendingCore.LoanPosition[](0);
    }

    /// @dev Builds a single-entry position array.
    function positions(IPool pool, uint256 amount) internal pure returns (ILendingCore.LoanPosition[] memory result) {
        result = new ILendingCore.LoanPosition[](1);
        result[0] = ILendingCore.LoanPosition({pool: pool, amount: amount});
    }

    /// @dev Builds a two-entry position array, one entry per pool.
    function positions(IPool poolA, uint256 amountA, IPool poolB, uint256 amountB)
        internal
        pure
        returns (ILendingCore.LoanPosition[] memory result)
    {
        result = new ILendingCore.LoanPosition[](2);
        result[0] = ILendingCore.LoanPosition({pool: poolA, amount: amountA});
        result[1] = ILendingCore.LoanPosition({pool: poolB, amount: amountB});
    }

    /// @dev Builds a three-entry position array, one entry per pool.
    function positions(IPool poolA, uint256 amountA, IPool poolB, uint256 amountB, IPool poolC, uint256 amountC)
        internal
        pure
        returns (ILendingCore.LoanPosition[] memory result)
    {
        result = new ILendingCore.LoanPosition[](3);
        result[0] = ILendingCore.LoanPosition({pool: poolA, amount: amountA});
        result[1] = ILendingCore.LoanPosition({pool: poolB, amount: amountB});
        result[2] = ILendingCore.LoanPosition({pool: poolC, amount: amountC});
    }
}
