// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Borrowable} from "src/pool/abstract/Borrowable.sol";

contract BorrowableHarness is Borrowable {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        address hookUpdater,
        address flashLoanConfigurator,
        address operatorFeeConfigurator,
        address initialHookReceiver,
        uint256 initialBeforeHookBitmap,
        uint256 initialAfterHookBitmap,
        address lendingCore_,
        bool initialFlashLoansEnabled,
        IERC20Metadata asset_,
        string calldata name_,
        string calldata symbol_,
        address debtToken_,
        address feeRegistry_,
        address operatorFeeRecipient_
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
        _initializeBorrowable(
            operatorFeeConfigurator, asset_, name_, symbol_, debtToken_, feeRegistry_, operatorFeeRecipient_
        );

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /// @dev Books underlying as idle liquidity, standing in for the inflow that would otherwise have brought it in.
    ///      The underlying itself must be sent to the pool separately; a bare transfer is a donation, which the pool
    ///      deliberately does not account for.
    function seedIdleLiquidity(uint256 assets) external {
        _idleLiquidity += assets;
    }

    function seedShares(address account, uint256 shares) external {
        _mint(account, shares);
    }

    function seedOperatorFeeShares(uint256 shares) external {
        _storedOperatorFeeShares = shares;
    }

    function seedOnlendFeeShares(uint256 shares) external {
        _storedOnlendFeeShares = shares;
    }

    function exposedAccrueInterest() external {
        _accrueInterest();
    }

    function exposedUpdateInterestRates() external {
        _updateInterestRates();
    }

    function validateDebtToken(address debtToken_) external view {
        _validateDebtToken(debtToken_);
    }

    function contractName() external pure returns (string memory name_) {
        return "BorrowableHarness";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }
}
