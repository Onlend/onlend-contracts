// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";

import {Borrowable} from "src/pool/abstract/Borrowable.sol";
import {FeeConstants} from "src/pool/lib/FeeConstants.sol";
import {MockDebtToken} from "../mocks/MockDebtToken.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockOnlendFeeRegistry} from "../mocks/MockOnlendFeeRegistry.sol";
import {BorrowableHarness} from "./mocks/BorrowableHarness.sol";

contract BorrowableFuzzTest is Test {
    // Covers very large token balances while keeping ERC-4626 conversions within uint256.
    uint256 internal constant MAX_ASSET_AMOUNT = 1e32;
    // Pool shares use the same decimals as the underlying; this caps aggregate seeded supply.
    uint256 internal constant MAX_SHARE_SUPPLY = 1e32;

    BorrowableHarness internal pool;
    MockERC20 internal asset;
    MockDebtToken internal debtToken;
    MockOnlendFeeRegistry internal feeRegistry;

    address internal defaultAdmin = makeAddr("defaultAdmin");
    address internal hookUpdater = makeAddr("hookUpdater");
    address internal operatorFeeConfigurator = makeAddr("operatorFeeConfigurator");
    address internal operatorFeeRecipient = makeAddr("operatorFeeRecipient");
    address internal onlendFeeRecipient = makeAddr("onlendFeeRecipient");
    address internal lendingCore = makeAddr("lendingCore");
    address internal borrower = makeAddr("borrower");
    address internal caller = makeAddr("caller");
    address internal receiver = makeAddr("receiver");
    address internal owner = makeAddr("owner");
    address internal other = makeAddr("other");

    function setUp() public {
        asset = new MockERC20();
        feeRegistry = new MockOnlendFeeRegistry(onlendFeeRecipient);
        BorrowableHarness poolImplementation = new BorrowableHarness();
        pool = BorrowableHarness(Clones.clone(address(poolImplementation)));

        debtToken = new MockDebtToken(address(pool), asset.decimals());
        pool.initialize(
            defaultAdmin,
            hookUpdater,
            address(0),
            operatorFeeConfigurator,
            address(0),
            0,
            0,
            lendingCore,
            false,
            asset,
            "fOnlend USD Coin",
            "fOnlend USDC",
            address(debtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );
    }

    // claimFeeShares()

    function testFuzz_claimFeeShares_ClaimsFullBalancesReportedByTotals(
        uint256 heldShares,
        uint256 operatorFeeShares,
        uint256 onlendFeeShares,
        uint256 idleLiquidity,
        uint256 debt,
        uint256 accrued,
        uint256 retained,
        uint16 fixedFeeBps,
        uint16 splitFeeBps
    ) public {
        heldShares = bound(heldShares, 0, MAX_SHARE_SUPPLY - 1);
        operatorFeeShares = bound(operatorFeeShares, 1, MAX_SHARE_SUPPLY - heldShares);
        onlendFeeShares = bound(onlendFeeShares, 0, MAX_SHARE_SUPPLY - heldShares - operatorFeeShares);
        idleLiquidity = bound(idleLiquidity, 0, MAX_ASSET_AMOUNT);
        debt = bound(debt, 0, MAX_ASSET_AMOUNT);
        // Interest is already counted in total assets, so it never exceeds them.
        accrued = bound(accrued, 0, idleLiquidity + debt);
        retained = bound(retained, 0, accrued);
        fixedFeeBps = uint16(bound(fixedFeeBps, 0, FeeConstants.MAX_FEE_BPS));
        splitFeeBps = uint16(bound(splitFeeBps, 0, FeeConstants.MAX_FEE_BPS));
        _setFeeConfig(fixedFeeBps, splitFeeBps);
        pool.seedShares(caller, heldShares);
        pool.seedOperatorFeeShares(operatorFeeShares);
        pool.seedOnlendFeeShares(onlendFeeShares);
        _seedIdleLiquidity(idleLiquidity);
        debtToken.seedDebt(borrower, debt);
        debtToken.setNextInterest(accrued, retained);
        uint256 expectedOperatorFeeShares = pool.totalOperatorFeeShares();
        uint256 expectedOnlendFeeShares = pool.totalOnlendFeeShares();

        vm.prank(caller);
        pool.claimFeeShares();

        assertEq(pool.balanceOf(operatorFeeRecipient), expectedOperatorFeeShares);
        assertEq(pool.balanceOf(onlendFeeRecipient), expectedOnlendFeeShares);
        assertEq(pool.totalOperatorFeeShares(), 0);
        assertEq(pool.totalOnlendFeeShares(), 0);
    }

    // deposit()

    function testFuzz_deposit_RevertsWhenPositiveAssetsWouldMintZeroShares(uint256 debt) public {
        debt = bound(debt, 2, MAX_ASSET_AMOUNT);
        pool.seedShares(other, 1);
        debtToken.seedDebt(borrower, debt);

        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(caller);
        pool.deposit(1, receiver);
    }

    // withdraw()

    function testFuzz_withdraw_AllowsAdvertisedMaximum(uint256 ownerShares, uint256 idleLiquidity, uint256 debt)
        public
    {
        ownerShares = bound(ownerShares, 1, MAX_SHARE_SUPPLY);
        idleLiquidity = bound(idleLiquidity, 1, MAX_ASSET_AMOUNT);
        // Keep the advertised maximum positive so every run executes a real withdrawal.
        uint256 minDebt = ownerShares > idleLiquidity ? ownerShares - idleLiquidity : 0;
        uint256 maxDebt = idleLiquidity * ownerShares - 1;
        if (maxDebt > MAX_ASSET_AMOUNT) maxDebt = MAX_ASSET_AMOUNT;
        debt = bound(debt, minDebt, maxDebt);
        pool.seedShares(owner, ownerShares);
        _seedIdleLiquidity(idleLiquidity);
        debtToken.seedDebt(borrower, debt);
        uint256 maxAssets = pool.maxWithdraw(owner);

        vm.prank(owner);
        pool.withdraw(maxAssets, receiver, owner);

        assertEq(asset.balanceOf(receiver), maxAssets);
    }

    // redeem()

    function testFuzz_redeem_AllowsAdvertisedMaximum(uint256 ownerShares, uint256 idleLiquidity, uint256 debt) public {
        ownerShares = bound(ownerShares, 1, MAX_SHARE_SUPPLY);
        idleLiquidity = bound(idleLiquidity, 1, MAX_ASSET_AMOUNT);
        // Keep the advertised maximum positive so every run executes a real redemption.
        uint256 minDebt = ownerShares > idleLiquidity ? ownerShares - idleLiquidity : 0;
        uint256 maxDebt = idleLiquidity * ownerShares - 1;
        if (maxDebt > MAX_ASSET_AMOUNT) maxDebt = MAX_ASSET_AMOUNT;
        debt = bound(debt, minDebt, maxDebt);
        pool.seedShares(owner, ownerShares);
        _seedIdleLiquidity(idleLiquidity);
        debtToken.seedDebt(borrower, debt);
        uint256 maxShares = pool.maxRedeem(owner);

        vm.prank(owner);
        uint256 assets = pool.redeem(maxShares, receiver, owner);

        assertEq(asset.balanceOf(receiver), assets);
    }

    // totalAssets()

    function testFuzz_totalAssets_IncreasesByIdleLiquidity(uint256 debt, uint256 idleLiquidity) public {
        debt = bound(debt, 0, MAX_ASSET_AMOUNT);
        idleLiquidity = bound(idleLiquidity, 1, MAX_ASSET_AMOUNT);
        debtToken.seedDebt(borrower, debt);
        uint256 totalAssetsBefore = pool.totalAssets();

        _seedIdleLiquidity(idleLiquidity);

        assertEq(pool.totalAssets() - totalAssetsBefore, idleLiquidity);
    }

    function testFuzz_totalAssets_IncreasesByDebt(uint256 idleLiquidity, uint256 debt) public {
        idleLiquidity = bound(idleLiquidity, 0, MAX_ASSET_AMOUNT);
        debt = bound(debt, 1, MAX_ASSET_AMOUNT);
        _seedIdleLiquidity(idleLiquidity);
        uint256 totalAssetsBefore = pool.totalAssets();

        debtToken.seedDebt(borrower, debt);

        assertEq(pool.totalAssets() - totalAssetsBefore, debt);
    }

    // totalSupply()

    /// @dev Accrual moves fee shares from the pending term to the stored one, and both are counted, so the supply the
    ///      pool prices against cannot move across the accrual that books it — whatever the shares, assets, debt or fees.
    function testFuzz_totalSupply_IsUnchangedByAccruingPendingInterest(
        uint256 heldShares,
        uint256 operatorFeeShares,
        uint256 onlendFeeShares,
        uint256 idleLiquidity,
        uint256 debt,
        uint256 accrued,
        uint256 retained,
        uint16 fixedFeeBps,
        uint16 splitFeeBps
    ) public {
        heldShares = bound(heldShares, 0, MAX_SHARE_SUPPLY);
        operatorFeeShares = bound(operatorFeeShares, 0, MAX_SHARE_SUPPLY - heldShares);
        onlendFeeShares = bound(onlendFeeShares, 0, MAX_SHARE_SUPPLY - heldShares - operatorFeeShares);
        idleLiquidity = bound(idleLiquidity, 0, MAX_ASSET_AMOUNT);
        debt = bound(debt, 0, MAX_ASSET_AMOUNT);
        // Interest is already counted in total assets, so it never exceeds them.
        accrued = bound(accrued, 0, idleLiquidity + debt);
        retained = bound(retained, 0, accrued);
        fixedFeeBps = uint16(bound(fixedFeeBps, 0, FeeConstants.MAX_FEE_BPS));
        splitFeeBps = uint16(bound(splitFeeBps, 0, FeeConstants.MAX_FEE_BPS));
        _setFeeConfig(fixedFeeBps, splitFeeBps);
        pool.seedShares(caller, heldShares);
        pool.seedOperatorFeeShares(operatorFeeShares);
        pool.seedOnlendFeeShares(onlendFeeShares);
        _seedIdleLiquidity(idleLiquidity);
        debtToken.seedDebt(borrower, debt);
        debtToken.setNextInterest(accrued, retained);
        uint256 totalSupplyBefore = pool.totalSupply();

        pool.exposedAccrueInterest();

        assertEq(pool.totalSupply(), totalSupplyBefore);
    }

    // maxWithdraw()

    function testFuzz_maxWithdraw_NeverExceedsIdleLiquidity(
        uint256 ownerShares,
        uint256 otherShares,
        uint256 idleLiquidity,
        uint256 debt,
        uint256 operatorFeeShares,
        uint256 onlendFeeShares
    ) public {
        ownerShares = bound(ownerShares, 1, MAX_SHARE_SUPPLY);
        otherShares = bound(otherShares, 0, MAX_SHARE_SUPPLY - ownerShares);
        operatorFeeShares = bound(operatorFeeShares, 0, MAX_SHARE_SUPPLY - ownerShares - otherShares);
        onlendFeeShares = bound(onlendFeeShares, 0, MAX_SHARE_SUPPLY - ownerShares - otherShares - operatorFeeShares);
        idleLiquidity = bound(idleLiquidity, 0, MAX_ASSET_AMOUNT);
        debt = bound(debt, 0, MAX_ASSET_AMOUNT);
        pool.seedShares(owner, ownerShares);
        pool.seedShares(other, otherShares);
        pool.seedOperatorFeeShares(operatorFeeShares);
        pool.seedOnlendFeeShares(onlendFeeShares);
        _seedIdleLiquidity(idleLiquidity);
        debtToken.seedDebt(borrower, debt);

        uint256 maxAssets = pool.maxWithdraw(owner);

        assertLe(maxAssets, idleLiquidity);
    }

    // maxRedeem()

    function testFuzz_maxRedeem_NeverExceedsOwnerShares(
        uint256 ownerShares,
        uint256 otherShares,
        uint256 idleLiquidity,
        uint256 debt,
        uint256 operatorFeeShares,
        uint256 onlendFeeShares
    ) public {
        ownerShares = bound(ownerShares, 1, MAX_SHARE_SUPPLY);
        otherShares = bound(otherShares, 0, MAX_SHARE_SUPPLY - ownerShares);
        operatorFeeShares = bound(operatorFeeShares, 0, MAX_SHARE_SUPPLY - ownerShares - otherShares);
        onlendFeeShares = bound(onlendFeeShares, 0, MAX_SHARE_SUPPLY - ownerShares - otherShares - operatorFeeShares);
        idleLiquidity = bound(idleLiquidity, 0, MAX_ASSET_AMOUNT);
        debt = bound(debt, 0, MAX_ASSET_AMOUNT);
        pool.seedShares(owner, ownerShares);
        pool.seedShares(other, otherShares);
        pool.seedOperatorFeeShares(operatorFeeShares);
        pool.seedOnlendFeeShares(onlendFeeShares);
        _seedIdleLiquidity(idleLiquidity);
        debtToken.seedDebt(borrower, debt);

        uint256 maxShares = pool.maxRedeem(owner);

        assertLe(maxShares, ownerShares);
    }

    function testFuzz_maxRedeem_NeverRequiresMoreThanIdleLiquidity(uint256 ownerShares, uint256 idleLiquidity) public {
        ownerShares = bound(ownerShares, 2, MAX_SHARE_SUPPLY);
        idleLiquidity = bound(idleLiquidity, 0, Math.min(ownerShares - 1, MAX_ASSET_AMOUNT));
        pool.seedShares(owner, ownerShares);
        _seedIdleLiquidity(idleLiquidity);
        debtToken.seedDebt(borrower, ownerShares - idleLiquidity);

        uint256 maxShares = pool.maxRedeem(owner);

        assertLe(pool.previewRedeem(maxShares), idleLiquidity);
    }

    // repay()

    function testFuzz_repay_WhenAmountDoesNotExceedDebtTransfersFullAmount(uint256 amount, uint256 remainingDebt)
        public
    {
        amount = bound(amount, 1, MAX_ASSET_AMOUNT);
        remainingDebt = bound(remainingDebt, 0, MAX_ASSET_AMOUNT);
        debtToken.seedDebt(receiver, amount + remainingDebt);
        _mintAndApprove(caller, amount);
        uint256 poolBalanceBefore = asset.balanceOf(address(pool));

        vm.prank(lendingCore);
        pool.repay(caller, amount, receiver);

        assertEq(asset.balanceOf(caller), 0);
        assertEq(asset.balanceOf(address(pool)) - poolBalanceBefore, amount);
    }

    function testFuzz_repay_WhenAmountExceedsDebtTransfersOnlyOutstandingDebt(uint256 debt, uint256 excess) public {
        debt = bound(debt, 1, MAX_ASSET_AMOUNT);
        excess = bound(excess, 1, MAX_ASSET_AMOUNT);
        uint256 requestedAmount = debt + excess;
        debtToken.seedDebt(receiver, debt);
        _mintAndApprove(caller, requestedAmount);
        uint256 poolBalanceBefore = asset.balanceOf(address(pool));

        vm.prank(lendingCore);
        pool.repay(caller, requestedAmount, receiver);

        assertEq(asset.balanceOf(caller), excess);
        assertEq(asset.balanceOf(address(pool)) - poolBalanceBefore, debt);
    }

    // writeOffDebt()

    function testFuzz_writeOffDebt_ReducesTotalAssetsByAccountDebt(
        uint256 idleLiquidity,
        uint256 debt,
        uint256 otherDebt
    ) public {
        idleLiquidity = bound(idleLiquidity, 0, MAX_ASSET_AMOUNT);
        debt = bound(debt, 1, MAX_ASSET_AMOUNT);
        otherDebt = bound(otherDebt, 0, MAX_ASSET_AMOUNT);
        _seedIdleLiquidity(idleLiquidity);
        debtToken.seedDebt(borrower, debt);
        debtToken.seedDebt(other, otherDebt);
        uint256 totalAssetsBefore = pool.totalAssets();

        vm.prank(lendingCore);
        uint256 writtenOff = pool.writeOffDebt(borrower);

        assertEq(writtenOff, debt);
        assertEq(totalAssetsBefore - pool.totalAssets(), debt);
    }

    function testFuzz_writeOffDebt_LeavesTotalSupplyUnchanged(
        uint256 heldShares,
        uint256 operatorFeeShares,
        uint256 onlendFeeShares,
        uint256 idleLiquidity,
        uint256 debt,
        uint256 accrued,
        uint256 retained,
        uint16 fixedFeeBps,
        uint16 splitFeeBps
    ) public {
        heldShares = bound(heldShares, 0, MAX_SHARE_SUPPLY);
        operatorFeeShares = bound(operatorFeeShares, 0, MAX_SHARE_SUPPLY - heldShares);
        onlendFeeShares = bound(onlendFeeShares, 0, MAX_SHARE_SUPPLY - heldShares - operatorFeeShares);
        idleLiquidity = bound(idleLiquidity, 0, MAX_ASSET_AMOUNT);
        debt = bound(debt, 1, MAX_ASSET_AMOUNT);
        // Interest is already counted in total assets, so it never exceeds them.
        accrued = bound(accrued, 0, idleLiquidity + debt);
        retained = bound(retained, 0, accrued);
        fixedFeeBps = uint16(bound(fixedFeeBps, 0, FeeConstants.MAX_FEE_BPS));
        splitFeeBps = uint16(bound(splitFeeBps, 0, FeeConstants.MAX_FEE_BPS));
        _setFeeConfig(fixedFeeBps, splitFeeBps);
        pool.seedShares(caller, heldShares);
        pool.seedOperatorFeeShares(operatorFeeShares);
        pool.seedOnlendFeeShares(onlendFeeShares);
        _seedIdleLiquidity(idleLiquidity);
        debtToken.seedDebt(borrower, debt);
        debtToken.setNextInterest(accrued, retained);
        uint256 totalSupplyBefore = pool.totalSupply();

        vm.prank(lendingCore);
        pool.writeOffDebt(borrower);

        assertEq(pool.totalSupply(), totalSupplyBefore);
    }

    /// @dev The pool only reads its fee configuration on a rate update, so one is run to pick up the new values.
    function _setFeeConfig(uint16 fixedFeeBps, uint16 splitFeeBps) internal {
        feeRegistry.setFeeConfig(fixedFeeBps, splitFeeBps);
        pool.exposedUpdateInterestRates();
    }

    /// @dev Puts underlying into the pool the way an inflow does: sent to the pool and booked as idle liquidity.
    ///      Sending it alone is a donation, which the pool does not account for.
    function _seedIdleLiquidity(uint256 assets) internal {
        asset.mint(address(pool), assets);
        pool.seedIdleLiquidity(assets);
    }

    function _mintAndApprove(address account, uint256 amount) internal {
        asset.mint(account, amount);
        vm.prank(account);
        asset.approve(address(pool), amount);
    }
}
