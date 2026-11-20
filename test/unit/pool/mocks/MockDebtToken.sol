// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IDebtToken} from "src/pool/debt/interfaces/IDebtToken.sol";

/// @dev Debt token stand-in for pool tests. Tracks debt through OpenZeppelin's `ERC20` and reports the decimals it was
///      constructed with, so a pool is exercised against a configurable dependency rather than against the real debt
///      token's own wiring. Accrual and rate updates report seeded values and emit the call they received, and every
///      entry point is ungated so tests can drive the mock directly.
contract MockDebtToken is ERC20, IDebtToken {
    address private immutable _POOL;
    uint8 private immutable _DECIMALS;

    uint256 private _nextAccrued;
    uint256 private _nextRetained;
    uint256 private _annualInterest;
    uint256 private _annualRetained;

    event SyncAccountCalled(address account);
    event AccrueInterestCalled();
    event UpdateBorrowRatesCalled(uint256 idleLiquidity);
    event MintCalled(address account, uint256 amount);
    event BurnCalled(address account, uint256 amount);

    constructor(address pool_, uint8 decimals_) ERC20("Mock Debt Token", "MDT") {
        _POOL = pool_;
        _DECIMALS = decimals_;
    }

    /// @inheritdoc IDebtToken
    function accrueInterest() external override(IDebtToken) returns (uint256 accrued, uint256 retained) {
        emit AccrueInterestCalled();

        (accrued, retained) = (_nextAccrued, _nextRetained);
        (_nextAccrued, _nextRetained) = (0, 0);
    }

    /// @inheritdoc IDebtToken
    function syncAccount(address account) external override(IDebtToken) {
        emit SyncAccountCalled(account);
    }

    /// @inheritdoc IDebtToken
    function updateBorrowRates(uint256 idleLiquidity) external override(IDebtToken) {
        emit UpdateBorrowRatesCalled(idleLiquidity);
    }

    /// @inheritdoc IDebtToken
    function mint(address account, uint256 amount) external override(IDebtToken) {
        emit MintCalled(account, amount);
        _mint(account, amount);
    }

    /// @inheritdoc IDebtToken
    function burn(address account, uint256 amount) external override(IDebtToken) {
        emit BurnCalled(account, amount);
        _burn(account, amount);
    }

    /// @dev Seeds the interest and retention the next accrual reports. Consumed on accrual, mirroring the real debt
    ///      token where accrued interest is handed over once and not accumulated.
    function setNextInterest(uint256 accrued, uint256 retained) external {
        (_nextAccrued, _nextRetained) = (accrued, retained);
    }

    /// @dev Seeds the annual interest reported to the pool. Unlike the accrued interest it sticks until set again,
    ///      mirroring the real debt token where it is derived from the stored rates rather than handed over.
    function setAnnualInterest(uint256 interest, uint256 retained) external {
        (_annualInterest, _annualRetained) = (interest, retained);
    }

    function seedDebt(address account, uint256 amount) external {
        _mint(account, amount);
    }

    /// @inheritdoc IDebtToken
    function pool() external view override(IDebtToken) returns (address) {
        return _POOL;
    }

    /// @inheritdoc IDebtToken
    function pendingInterest() external view override(IDebtToken) returns (uint256, uint256) {
        return (_nextAccrued, _nextRetained);
    }

    /// @inheritdoc IDebtToken
    function annualInterest() external view override(IDebtToken) returns (uint256, uint256) {
        return (_annualInterest, _annualRetained);
    }

    function contractName() external pure returns (string memory name_) {
        return "MockDebtToken";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function decimals() public view override(ERC20) returns (uint8) {
        return _DECIMALS;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override(IERC165) returns (bool) {
        return interfaceId == type(IDebtToken).interfaceId || interfaceId == type(IERC20).interfaceId
            || interfaceId == type(IVersioned).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
