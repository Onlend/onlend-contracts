// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {BasePool} from "src/pool/abstract/BasePool.sol";
import {Collateralisable} from "src/pool/abstract/Collateralisable.sol";

contract CollateralisableHarness is Collateralisable {
    address private _asset;

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
        bool initialFlashLoansEnabled,
        address collateralToken_,
        uint8 assetDecimals
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
        _initializeCollateralisable(collateralToken_, assetDecimals);

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    function validateCollateralToken(address collateralToken_) external view {
        _validateCollateralToken(collateralToken_);
    }

    function contractName() external pure returns (string memory name_) {
        return "CollateralisableHarness";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function asset() public pure override(BasePool) returns (address) {
        return address(0);
    }

    function totalAssets() public view override(BasePool) returns (uint256) {
        return totalCollateral();
    }

    function _depositCollateral(address, uint256 assets, uint256, address receiver)
        internal
        override(BasePool)
        returns (uint256, uint256)
    {
        _collateralToken.mint(receiver, assets);

        return (assets, 0);
    }

    function _withdrawCollateral(address caller, uint256 assets, uint256, address)
        internal
        override(BasePool)
        returns (uint256, uint256)
    {
        _collateralToken.burn(caller, assets);

        return (assets, 0);
    }

    function _seizeCollateral(address violator, uint256 assets, address)
        internal
        override(BasePool)
        returns (uint256, uint256)
    {
        _collateralToken.burn(violator, assets);

        return (assets, 0);
    }
}
