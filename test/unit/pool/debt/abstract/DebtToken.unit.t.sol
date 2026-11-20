// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {DebtToken} from "src/pool/debt/abstract/DebtToken.sol";
import {IDebtToken} from "src/pool/debt/interfaces/IDebtToken.sol";
import {DebtTokenHarness} from "./mocks/DebtTokenHarness.sol";

contract DebtTokenTest is Test {
    DebtTokenHarness implementation;
    DebtTokenHarness debtToken;

    address pool = makeAddr("pool");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    string constant NAME = "dOnlend USD Coin";
    string constant SYMBOL = "dOnlend USDC";
    // Deliberately not eighteen, so a decimals getter falling back to the ERC-20 default would be visible.
    uint8 constant DECIMALS = 6;

    uint256 constant AMOUNT = 1000e18;
    uint256 constant IDLE_LIQUIDITY = 5000e18;

    event SyncAccountCalled(address account);
    event AccrueInterestCalled();
    event UpdateBorrowRatesCalled(uint256 idleLiquidity);
    event MintCalled(address account, uint256 amount);
    event BurnCalled(address account, uint256 amount);

    function setUp() public {
        implementation = new DebtTokenHarness();
        debtToken = DebtTokenHarness(Clones.clone(address(implementation)));
        debtToken.initialize(pool, NAME, SYMBOL, DECIMALS);
    }

    // initialize()

    function test_Initialize_SetsNameAndSymbol() public view {
        assertEq(debtToken.name(), NAME);
        assertEq(debtToken.symbol(), SYMBOL);
    }

    function test_Initialize_SetsPool() public view {
        assertEq(debtToken.pool(), pool);
    }

    function test_Initialize_SetsDecimals() public view {
        assertEq(debtToken.decimals(), DECIMALS);
    }

    // accrueInterest()

    function test_AccrueInterest_CallsInternalAccrueInterest() public {
        vm.expectEmit(address(debtToken));
        emit AccrueInterestCalled();

        vm.prank(pool);
        debtToken.accrueInterest();
    }

    function test_AccrueInterest_ReturnsInterestFromInternalAccrueInterest() public {
        debtToken.setNextInterest(100, 20);

        vm.prank(pool);
        (uint256 accrued, uint256 retained) = debtToken.accrueInterest();

        assertEq(accrued, 100);
        assertEq(retained, 20);
    }

    function test_AccrueInterest_Revert_NotPoolCaller() public {
        vm.expectRevert(DebtToken.NotPoolCaller.selector);
        vm.prank(alice);
        debtToken.accrueInterest();
    }

    // syncAccount()

    function test_SyncAccount_CallsInternalSyncAccount() public {
        vm.expectEmit(address(debtToken));
        emit SyncAccountCalled(alice);

        vm.prank(pool);
        debtToken.syncAccount(alice);
    }

    function test_SyncAccount_Revert_NotPoolCaller() public {
        vm.expectRevert(DebtToken.NotPoolCaller.selector);
        vm.prank(alice);
        debtToken.syncAccount(alice);
    }

    // updateBorrowRates()

    function test_UpdateBorrowRates_CallsInternalUpdateBorrowRatesWithIdleLiquidity() public {
        vm.expectEmit(address(debtToken));
        emit UpdateBorrowRatesCalled(IDLE_LIQUIDITY);

        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);
    }

    function test_UpdateBorrowRates_Revert_NotPoolCaller() public {
        vm.expectRevert(DebtToken.NotPoolCaller.selector);
        vm.prank(alice);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);
    }

    // mint()

    function test_Mint_IncreasesBalance() public {
        vm.expectEmit(address(debtToken));
        emit MintCalled(alice, AMOUNT);

        vm.prank(pool);
        debtToken.mint(alice, AMOUNT);

        assertEq(debtToken.balanceOf(alice), AMOUNT);
    }

    function test_Mint_Revert_NotPoolCaller() public {
        vm.expectRevert(DebtToken.NotPoolCaller.selector);
        vm.prank(alice);
        debtToken.mint(alice, AMOUNT);
    }

    function test_Mint_Revert_ZeroAmount() public {
        vm.expectRevert(DebtToken.ZeroAmount.selector);
        vm.prank(pool);
        debtToken.mint(alice, 0);
    }

    // burn()

    function test_Burn_DecreasesBalance() public {
        vm.prank(pool);
        debtToken.mint(alice, AMOUNT);

        vm.expectEmit(address(debtToken));
        emit BurnCalled(alice, AMOUNT);

        vm.prank(pool);
        debtToken.burn(alice, AMOUNT);

        assertEq(debtToken.balanceOf(alice), 0);
    }

    function test_Burn_Revert_NotPoolCaller() public {
        vm.prank(pool);
        debtToken.mint(alice, AMOUNT);

        vm.expectRevert(DebtToken.NotPoolCaller.selector);
        vm.prank(alice);
        debtToken.burn(alice, AMOUNT);
    }

    function test_Burn_Revert_ZeroAmount() public {
        vm.prank(pool);
        debtToken.mint(alice, AMOUNT);

        vm.expectRevert(DebtToken.ZeroAmount.selector);
        vm.prank(pool);
        debtToken.burn(alice, 0);
    }

    // supportsInterface()

    function test_SupportsInterface_DebtToken_ReturnsTrue() public view {
        assertTrue(debtToken.supportsInterface(type(IDebtToken).interfaceId));
    }

    function test_SupportsInterface_ERC20_ReturnsTrue() public view {
        assertTrue(debtToken.supportsInterface(type(IERC20).interfaceId));
    }

    function test_SupportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(debtToken.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_SupportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(debtToken.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(debtToken.supportsInterface(bytes4(0xffffffff)));
    }

    // transfer()

    function test_Transfer_Revert_FunctionNotSupported() public {
        vm.expectRevert(DebtToken.FunctionNotSupported.selector);
        vm.prank(alice);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        debtToken.transfer(bob, AMOUNT);
    }

    // transferFrom()

    function test_TransferFrom_Revert_FunctionNotSupported() public {
        vm.expectRevert(DebtToken.FunctionNotSupported.selector);
        vm.prank(alice);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        debtToken.transferFrom(alice, bob, AMOUNT);
    }

    // approve()

    function test_Approve_Revert_FunctionNotSupported() public {
        vm.expectRevert(DebtToken.FunctionNotSupported.selector);
        vm.prank(alice);
        debtToken.approve(bob, AMOUNT);
    }
}
