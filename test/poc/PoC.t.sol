// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {PoCBase} from "./PoCBase.t.sol";

/// @notice Template for a proof of concept. Copy this file, rename the test, and replace its body.
contract PoC is PoCBase {
    /// @dev Example: a borrower is liquidated after the price of their collateral falls.
    function test_PoC() public {
        _supply(alice, usdcPool, 100_000e6);
        _depositCollateral(bob, wethPool, 10e18);
        _borrow(bob, usdcPool, 15_000e6);
        // 10 WETH at $1,800 with an 80% collateral factor backs $14,400 against $15,000 of debt: health 0.96.
        _setPrice(wethPool, 1800e18);
        assertTrue(_isLiquidatable(bob));

        // At health 0.96 WETH pays a 5.2% bonus, so repaying $5,000 entitles carol to up to $5,260 of WETH.
        _liquidate(carol, bob, wethPool, 2.92e18, usdcPool, 5000e6);

        assertEq(weth.balanceOf(carol), 2.92e18);
        assertEq(usdcPool.debtOf(bob), 10_000e6);
        assertFalse(_isLiquidatable(bob));
    }
}
