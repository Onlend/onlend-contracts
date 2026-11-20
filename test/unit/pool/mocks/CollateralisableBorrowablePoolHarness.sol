// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {CollateralisableBorrowablePool} from "src/pool/CollateralisableBorrowablePool.sol";
import {ICollateralToken} from "src/pool/collateral/interfaces/ICollateralToken.sol";

contract CollateralisableBorrowablePoolHarness is CollateralisableBorrowablePool {
    /// @dev Books underlying as idle liquidity, standing in for the inflow that would otherwise have brought it in.
    ///      The underlying itself must be sent to the pool separately; a bare transfer is a donation, which the pool
    ///      deliberately does not account for.
    function seedIdleLiquidity(uint256 assets) external {
        _idleLiquidity += assets;
    }

    function seedShares(address account, uint256 shares) external {
        _mint(account, shares);
    }

    function seedCollateralPosition(address account, uint256 shares) external {
        _mint(address(this), shares);
        ICollateralToken(this.collateralToken()).mint(account, shares);
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
}
