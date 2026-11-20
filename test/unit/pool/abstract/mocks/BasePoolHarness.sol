// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {BasePool} from "src/pool/abstract/BasePool.sol";

contract BasePoolHarness is BasePool {
    bool public shouldRevert;
    address private _asset;
    bool private _overrideCollateralResult;
    uint256 private _collateralResultAssets;
    uint256 private _collateralResultShares;
    uint256 public repayment;
    uint256 public writtenOff;

    event DepositCollateralCalled(address caller, uint256 assets, uint256 shares, address receiver);
    event WithdrawCollateralCalled(address caller, uint256 assets, uint256 shares, address receiver);
    event SeizeCollateralCalled(address violator, uint256 assets, address receiver);
    event BorrowCalled(address caller, uint256 amount, address receiver);
    event RepayCalled(address caller, uint256 amount, address receiver);
    event WriteOffDebtCalled(address account);

    error HarnessReverted();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        address hookUpdater,
        address flashLoanConfigurator,
        address initialHookReceiver,
        uint256 initialBeforeHookBitmap,
        uint256 initialAfterHookBitmap,
        address lendingCore_,
        bool initialFlashLoansEnabled
    ) external initializer {
        __AccessControlEnumerable_init();
        _initializePool(
            hookUpdater,
            flashLoanConfigurator,
            initialHookReceiver,
            initialBeforeHookBitmap,
            initialAfterHookBitmap,
            lendingCore_,
            initialFlashLoansEnabled
        );

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    function setShouldRevert(bool shouldRevert_) external {
        shouldRevert = shouldRevert_;
    }

    function setAsset(address asset_) external {
        _asset = asset_;
    }

    /// @notice Makes the collateral operations resolve the request to these amounts instead of echoing it back,
    ///         so a test can tell the requested amounts apart from the resolved ones.
    function setCollateralResult(uint256 assets, uint256 shares) external {
        _overrideCollateralResult = true;
        _collateralResultAssets = assets;
        _collateralResultShares = shares;
    }

    function setRepayment(uint256 repayment_) external {
        repayment = repayment_;
    }

    function setWrittenOff(uint256 writtenOff_) external {
        writtenOff = writtenOff_;
    }

    function validateTokenDecimals(address token, uint8 expected) external view {
        _validateTokenDecimals(token, expected);
    }

    function contractName() external pure returns (string memory name_) {
        return "BasePoolHarness";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function asset() public view override(BasePool) returns (address) {
        return _asset;
    }

    function totalAssets() public pure override(BasePool) returns (uint256) {
        return 0;
    }

    function _depositCollateral(address caller, uint256 assets, uint256 shares, address receiver)
        internal
        override
        returns (uint256, uint256)
    {
        if (shouldRevert) revert HarnessReverted();

        emit DepositCollateralCalled(caller, assets, shares, receiver);

        return _collateralResult(assets, shares);
    }

    function _withdrawCollateral(address caller, uint256 assets, uint256 shares, address receiver)
        internal
        override
        returns (uint256, uint256)
    {
        if (shouldRevert) revert HarnessReverted();

        emit WithdrawCollateralCalled(caller, assets, shares, receiver);

        return _collateralResult(assets, shares);
    }

    function _seizeCollateral(address violator, uint256 assets, address receiver)
        internal
        override
        returns (uint256, uint256)
    {
        if (shouldRevert) revert HarnessReverted();

        emit SeizeCollateralCalled(violator, assets, receiver);

        return _collateralResult(assets, 0);
    }

    function _borrow(address caller, uint256 amount, address receiver) internal override {
        if (shouldRevert) revert HarnessReverted();

        emit BorrowCalled(caller, amount, receiver);
    }

    function _repay(address caller, uint256 amount, address receiver) internal override returns (uint256) {
        if (shouldRevert) revert HarnessReverted();

        emit RepayCalled(caller, amount, receiver);

        return repayment;
    }

    function _writeOffDebt(address account) internal override returns (uint256) {
        if (shouldRevert) revert HarnessReverted();

        emit WriteOffDebtCalled(account);

        return writtenOff;
    }

    function _collateralResult(uint256 assets, uint256 shares) private view returns (uint256, uint256) {
        if (!_overrideCollateralResult) return (assets, shares);

        return (_collateralResultAssets, _collateralResultShares);
    }
}
