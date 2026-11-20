// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {MultiInterestDebtToken} from "src/pool/debt/MultiInterestDebtToken.sol";

contract MultiInterestDebtTokenHarness is MultiInterestDebtToken {
    function updateIrmBorrowIndex(address irmId) external returns (uint256 accrued, uint256 retained) {
        return _updateIrmBorrowIndex(irmId);
    }

    /// @dev Seeds `lastUpdateTs` directly, so the fresh-index precondition of `updateBorrowRates` can be satisfied (or
    ///      violated) without routing through `accrueInterest`.
    function setLastUpdateTs(uint256 ts) external {
        _lastUpdateTs = ts;
    }

    /// @dev Seeds the stored borrow rate for `irmId` directly, so index accrual can be exercised without routing
    ///      through the rate subsystem (`updateBorrowRates`).
    function setIrmBorrowRate(address irmId, uint256 borrowRate) external {
        _irmData[irmId].borrowRate = borrowRate;
    }

    /// @dev Seeds the stored borrow index for `irmId` directly, so accrual can start from an index other than one.
    function setIrmStoredBorrowIndex(address irmId, uint256 storedBorrowIndex) external {
        _irmData[irmId].storedBorrowIndex = storedBorrowIndex;
    }

    /// @dev Seeds the stored retention rate for `irmId` directly, so retention can be exercised without routing
    ///      through the rate subsystem (`updateBorrowRates`).
    function setIrmRetentionRate(address irmId, uint256 retentionRate) external {
        _irmData[irmId].retentionRate = retentionRate;
    }

    /// @dev Seeds the stored total scaled debt for `irmId` directly, so bucket-level accrual and aggregation can be
    ///      exercised without routing through the mint path and the account balances it moves.
    function setIrmTotalScaledDebt(address irmId, uint256 totalScaledDebt) external {
        _irmData[irmId].totalScaledDebt = totalScaledDebt;
    }
}
