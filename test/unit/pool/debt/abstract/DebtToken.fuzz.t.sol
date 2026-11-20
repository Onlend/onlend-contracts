// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {DebtTokenHarness} from "./mocks/DebtTokenHarness.sol";

contract DebtTokenFuzzTest is Test {
    DebtTokenHarness debtToken;

    address pool = makeAddr("pool");

    string constant NAME = "dOnlend USD Coin";
    string constant SYMBOL = "dOnlend USDC";
    uint8 constant DECIMALS = 6;

    event SyncAccountCalled(address account);
    event AccrueInterestCalled();
    event UpdateBorrowRatesCalled(uint256 idleLiquidity);
    event MintCalled(address account, uint256 amount);
    event BurnCalled(address account, uint256 amount);

    function setUp() public {
        DebtTokenHarness implementation = new DebtTokenHarness();
        debtToken = DebtTokenHarness(Clones.clone(address(implementation)));
        debtToken.initialize(pool, NAME, SYMBOL, DECIMALS);
    }

    // accrueInterest()

    function testFuzz_AccrueInterest_CallsInternalAccrueInterest(uint8 calls) public {
        for (uint256 i = 0; i < calls; i++) {
            vm.expectEmit(address(debtToken));
            emit AccrueInterestCalled();

            vm.prank(pool);
            debtToken.accrueInterest();
        }
    }

    // syncAccount()

    function testFuzz_SyncAccount_CallsInternalSyncAccountWithAccount(address account) public {
        vm.expectEmit(address(debtToken));
        emit SyncAccountCalled(account);

        vm.prank(pool);
        debtToken.syncAccount(account);
    }

    // updateBorrowRates()

    function testFuzz_UpdateBorrowRates_ForwardsIdleLiquidityToInternalUpdateBorrowRates(uint256 idleLiquidity) public {
        vm.expectEmit(address(debtToken));
        emit UpdateBorrowRatesCalled(idleLiquidity);

        vm.prank(pool);
        debtToken.updateBorrowRates(idleLiquidity);
    }

    // mint()

    function testFuzz_Mint_IncreasesBalanceByAmount(address account, uint256 amount) public {
        vm.assume(account != address(0));
        amount = bound(amount, 1, type(uint256).max);

        vm.expectEmit(address(debtToken));
        emit MintCalled(account, amount);

        vm.prank(pool);
        debtToken.mint(account, amount);

        assertEq(debtToken.balanceOf(account), amount);
    }

    // burn()

    function testFuzz_Burn_DecreasesBalanceByAmount(address account, uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(account != address(0));
        mintAmount = bound(mintAmount, 1, type(uint256).max);
        burnAmount = bound(burnAmount, 1, mintAmount);

        vm.prank(pool);
        debtToken.mint(account, mintAmount);

        vm.expectEmit(address(debtToken));
        emit BurnCalled(account, burnAmount);

        vm.prank(pool);
        debtToken.burn(account, burnAmount);

        assertEq(debtToken.balanceOf(account), mintAmount - burnAmount);
    }
}
