// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IIRM} from "../interfaces/IIRM.sol";
import {IRMConstants} from "../libraries/IRMConstants.sol";

/// @title Capped Interest Rate Model
/// @notice Reusable base that caps the borrow rate returned by an IRM at 1,000% and the retention rate at 100%.
/// @dev Applies the caps after the concrete implementation calculates each rate. Concrete `IIRM` implementations should
///      inherit this contract or enforce equivalent bounds themselves.
abstract contract CappedIRM is IIRM {
    /// @inheritdoc IIRM
    function borrowRate(uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        override
        returns (uint256)
    {
        return Math.min(_borrowRate(idleLiquidity, totalDebt, totalIrmDebt), IRMConstants.MAX_BORROW_RATE);
    }

    /// @inheritdoc IIRM
    function previewBorrowRate(uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        view
        override
        returns (uint256)
    {
        return Math.min(_previewBorrowRate(idleLiquidity, totalDebt, totalIrmDebt), IRMConstants.MAX_BORROW_RATE);
    }

    /// @inheritdoc IIRM
    function retentionRate(uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        view
        override
        returns (uint256)
    {
        return Math.min(_retentionRate(idleLiquidity, totalDebt, totalIrmDebt), IRMConstants.MAX_RETENTION_RATE);
    }

    /// @notice Calculates the borrow rate before applying the 1,000% cap, updating any state the IRM keeps.
    /// @param idleLiquidity Current idle liquidity.
    /// @param totalDebt Current total debt.
    /// @param totalIrmDebt Current total debt using this IRM.
    /// @return Uncapped borrow rate, scaled to 18dp.
    function _borrowRate(uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        internal
        virtual
        returns (uint256);

    /// @notice Calculates the borrow rate `_borrowRate` would return before applying the 1,000% cap, without updating
    ///         state.
    /// @param idleLiquidity Current idle liquidity.
    /// @param totalDebt Current total debt.
    /// @param totalIrmDebt Current total debt using this IRM.
    /// @return Uncapped borrow rate, scaled to 18dp.
    function _previewBorrowRate(uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        internal
        view
        virtual
        returns (uint256);

    /// @notice Calculates the retention rate before applying the 100% cap.
    /// @param idleLiquidity Current idle liquidity.
    /// @param totalDebt Current total debt.
    /// @param totalIrmDebt Current total debt using this IRM.
    /// @return Uncapped retention rate, scaled to 18dp.
    function _retentionRate(uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        internal
        view
        virtual
        returns (uint256);
}
