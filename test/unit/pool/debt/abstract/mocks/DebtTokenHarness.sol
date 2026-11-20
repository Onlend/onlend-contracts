// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {DebtToken} from "src/pool/debt/abstract/DebtToken.sol";

contract DebtTokenHarness is DebtToken {
    uint256 private _nextAccrued;
    uint256 private _nextRetained;
    uint256 private _annualInterest;
    uint256 private _annualRetained;

    event SyncAccountCalled(address account);
    event AccrueInterestCalled();
    event UpdateBorrowRatesCalled(uint256 idleLiquidity);
    event MintCalled(address account, uint256 amount);
    event BurnCalled(address account, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(address pool_, string memory name_, string memory symbol_, uint8 decimals_)
        external
        initializer
    {
        _initializeDebtToken(pool_, name_, symbol_, decimals_);
    }

    /// @dev Seeds the interest and retention the next accrual reports, so the pass-through from `_accrueInterest` to
    ///      `accrueInterest` can be asserted without any interest model behind it.
    function setNextInterest(uint256 accrued, uint256 retained) external {
        (_nextAccrued, _nextRetained) = (accrued, retained);
    }

    /// @dev Seeds the annual interest reported to the pool, so the getter can be driven without any interest model
    ///      behind it.
    function setAnnualInterest(uint256 interest, uint256 retained) external {
        (_annualInterest, _annualRetained) = (interest, retained);
    }

    function pendingInterest() external view returns (uint256, uint256) {
        return (_nextAccrued, _nextRetained);
    }

    function annualInterest() external view returns (uint256, uint256) {
        return (_annualInterest, _annualRetained);
    }

    function contractName() external pure returns (string memory name_) {
        return "DebtTokenHarness";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function _syncAccount(address account) internal override {
        emit SyncAccountCalled(account);
    }

    function _accrueInterest() internal override returns (uint256 accrued, uint256 retained) {
        emit AccrueInterestCalled();
        return (_nextAccrued, _nextRetained);
    }

    function _updateBorrowRates(uint256 idleLiquidity) internal override {
        emit UpdateBorrowRatesCalled(idleLiquidity);
    }

    function _mintDebt(address account, uint256 amount) internal override {
        emit MintCalled(account, amount);
        _mint(account, amount);
    }

    function _burnDebt(address account, uint256 amount) internal override {
        emit BurnCalled(account, amount);
        _burn(account, amount);
    }
}
