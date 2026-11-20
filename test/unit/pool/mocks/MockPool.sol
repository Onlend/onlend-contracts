// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";

contract MockPool is IPool {
    address private _asset;
    uint256 private _totalAssets;
    uint256 private _totalCollateral;
    uint256 private _totalDebt;
    uint256 private _resolvedAssets;
    uint256 private _resolvedShares;
    uint256 private _repayment;
    mapping(address account => uint256) private _collateralOf;
    mapping(address account => uint256) private _debtOf;
    address private _withdrawAccount;
    uint256 private _collateralOfAfterWithdraw;
    address private _borrowAccount;
    uint256 private _debtOfAfterBorrow;
    address private _repayAccount;
    uint256 private _debtOfAfterRepay;
    address private _seizeAccount;
    uint256 private _collateralOfAfterSeize;
    address private _borrowReentryTarget;
    bytes private _borrowReentryData;

    function setAsset(address asset_) external {
        _asset = asset_;
    }

    function setTotals(uint256 totalAssets_, uint256 totalCollateral_, uint256 totalDebt_) external {
        _totalAssets = totalAssets_;
        _totalCollateral = totalCollateral_;
        _totalDebt = totalDebt_;
    }

    /// @notice Sets the amounts the collateral operations report having resolved the request to.
    function setResolvedCollateral(uint256 assets, uint256 shares) external {
        _resolvedAssets = assets;
        _resolvedShares = shares;
    }

    function setRepayment(uint256 repayment_) external {
        _repayment = repayment_;
    }

    function setCollateralOf(address account, uint256 collateral) external {
        _collateralOf[account] = collateral;
    }

    function setDebtOf(address account, uint256 debt) external {
        _debtOf[account] = debt;
    }

    /// @notice Sets the collateral `account` holds once a withdrawal from it has run, so a test can tell a loan
    ///         built after the withdrawal from one built before it.
    function setCollateralOfAfterWithdraw(address account, uint256 collateral) external {
        _withdrawAccount = account;
        _collateralOfAfterWithdraw = collateral;
    }

    /// @notice Sets the debt `account` owes once a borrow by it has run, so a test can tell a loan built after the
    ///         borrow from one built before it.
    function setDebtOfAfterBorrow(address account, uint256 debt) external {
        _borrowAccount = account;
        _debtOfAfterBorrow = debt;
    }

    /// @notice Sets the debt `account` owes once a repayment of it has run, so a test can tell a loan built after the
    ///         repayment from one built before it.
    function setDebtOfAfterRepay(address account, uint256 debt) external {
        _repayAccount = account;
        _debtOfAfterRepay = debt;
    }

    /// @notice Sets the collateral `account` holds once a seizure from it has run, so a test can tell a loan built
    ///         after the seizure from one built before it.
    function setCollateralOfAfterSeize(address account, uint256 collateral) external {
        _seizeAccount = account;
        _collateralOfAfterSeize = collateral;
    }

    /// @notice Makes a borrow call `target` with `data` once it has run, reverting with the call's revert data if it
    ///         fails, as a borrowed asset that calls its recipient on transfer would.
    function setBorrowReentry(address target, bytes calldata data) external {
        _borrowReentryTarget = target;
        _borrowReentryData = data;
    }

    function depositCollateral(address, uint256, uint256, address) external view returns (uint256, uint256) {
        return (_resolvedAssets, _resolvedShares);
    }

    function withdrawCollateral(address caller, uint256, uint256, address) external returns (uint256, uint256) {
        if (caller == _withdrawAccount) _collateralOf[caller] = _collateralOfAfterWithdraw;
        return (_resolvedAssets, _resolvedShares);
    }

    function seizeCollateral(address violator, uint256, address) external returns (uint256, uint256) {
        if (violator == _seizeAccount) _collateralOf[violator] = _collateralOfAfterSeize;
        return (_resolvedAssets, _resolvedShares);
    }

    function borrow(address caller, uint256, address) external {
        if (caller == _borrowAccount) _debtOf[caller] = _debtOfAfterBorrow;
        if (_borrowReentryTarget != address(0)) Address.functionCall(_borrowReentryTarget, _borrowReentryData);
    }

    function repay(address, uint256, address receiver) external returns (uint256) {
        if (receiver == _repayAccount) _debtOf[receiver] = _debtOfAfterRepay;
        return _repayment;
    }

    function writeOffDebt(address account) external returns (uint256 writtenOff) {
        writtenOff = _debtOf[account];
        _debtOf[account] = 0;
    }

    function asset() external view returns (address) {
        return _asset;
    }

    function lendingCore() external pure returns (address) {
        return address(0);
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }

    function totalCollateral() external view returns (uint256) {
        return _totalCollateral;
    }

    function totalDebt() external view returns (uint256) {
        return _totalDebt;
    }

    function collateralOf(address account) external view returns (uint256) {
        return _collateralOf[account];
    }

    function debtOf(address account) external view returns (uint256) {
        return _debtOf[account];
    }

    function contractName() external pure returns (string memory name_) {
        return "MockPool";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IPool).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
