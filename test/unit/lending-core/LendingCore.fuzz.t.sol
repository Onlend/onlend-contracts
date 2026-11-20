// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {Authorisable} from "src/authorisation/abstract/Authorisable.sol";
import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {LendingCore} from "src/lending-core/LendingCore.sol";
import {MockLoanEvaluator} from "../loan/mocks/MockLoanEvaluator.sol";
import {MockLiquidationEngine} from "../liquidation/mocks/MockLiquidationEngine.sol";
import {MockPool} from "../pool/mocks/MockPool.sol";
import {MockHookReceiver} from "../hooks/mocks/MockHookReceiver.sol";
import {LoanHelpers} from "../../helpers/LoanHelpers.sol";

contract LendingCoreFuzzTest is Test {
    address internal poolLister;
    address internal hookUpdater;
    address internal badDebtConfigurator;

    MockLoanEvaluator internal loanEvaluator;
    MockLiquidationEngine internal liquidationEngine;
    MockPool internal pool;
    MockHookReceiver internal hookReceiver;
    LendingCore internal lendingCore;

    function setUp() public {
        poolLister = makeAddr("poolLister");
        hookUpdater = makeAddr("hookUpdater");
        badDebtConfigurator = makeAddr("badDebtConfigurator");

        loanEvaluator = new MockLoanEvaluator();
        liquidationEngine = new MockLiquidationEngine();
        pool = new MockPool();
        hookReceiver = new MockHookReceiver();

        LendingCore implementation = new LendingCore();
        lendingCore = LendingCore(Clones.clone(address(implementation)));
        lendingCore.initialize(
            address(loanEvaluator),
            address(liquidationEngine),
            makeAddr("defaultAdmin"),
            hookUpdater,
            address(0),
            0,
            0,
            poolLister,
            makeAddr("loanUpdater"),
            makeAddr("liquidationUpdater"),
            badDebtConfigurator,
            address(0),
            false,
            "",
            new address[](0)
        );
    }

    // depositCollateral()

    function testFuzz_depositCollateral_ForwardsToPool(uint256 assets, uint256 shares, address user, address onBehalfOf)
        public
    {
        assumeNotForgeAddress(user);
        _addPool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.depositCollateral, (user, assets, shares, onBehalfOf)));

        vm.prank(user);
        lendingCore.depositCollateral(IPool(address(pool)), assets, shares, onBehalfOf);
    }

    function testFuzz_depositCollateral_FiresHooksWithEncodedData(
        uint256 assets,
        uint256 shares,
        address user,
        address onBehalfOf,
        uint256 resolvedAssets,
        uint256 resolvedShares
    ) public {
        assumeNotForgeAddress(user);
        _addPool();
        pool.setResolvedCollateral(resolvedAssets, resolvedShares);
        _enableHooks(ActionLib.LC_DEPOSIT_COLLATERAL);
        bytes memory beforeData = abi.encode(onBehalfOf, user, user, address(pool), assets, shares);
        bytes memory afterData = abi.encode(onBehalfOf, user, user, address(pool), resolvedAssets, resolvedShares);

        _expectBeforeAndAfterHooks(ActionLib.LC_DEPOSIT_COLLATERAL, beforeData, afterData);

        vm.prank(user);
        lendingCore.depositCollateral(IPool(address(pool)), assets, shares, onBehalfOf);
    }

    function testFuzz_depositCollateral_ReturnsAmountsResolvedByPool(
        uint256 assets,
        uint256 shares,
        address user,
        address onBehalfOf,
        uint256 resolvedAssets,
        uint256 resolvedShares
    ) public {
        assumeNotForgeAddress(user);
        _addPool();
        pool.setResolvedCollateral(resolvedAssets, resolvedShares);

        vm.prank(user);
        (uint256 assetsDeposited, uint256 sharesMinted) =
            lendingCore.depositCollateral(IPool(address(pool)), assets, shares, onBehalfOf);

        assertEq(assetsDeposited, resolvedAssets);
        assertEq(sharesMinted, resolvedShares);
    }

    // withdrawCollateral()

    function testFuzz_withdrawCollateral_ForwardsToPool(uint256 assets, uint256 shares, address user, address receiver)
        public
    {
        assumeNotForgeAddress(user);
        _addPool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.withdrawCollateral, (user, assets, shares, receiver)));

        vm.prank(user);
        lendingCore.withdrawCollateral(IPool(address(pool)), assets, shares, user, receiver);
    }

    function testFuzz_withdrawCollateral_FiresHooksWithEncodedData(
        uint256 assets,
        uint256 shares,
        address user,
        address receiver,
        uint256 resolvedAssets,
        uint256 resolvedShares
    ) public {
        assumeNotForgeAddress(user);
        _addPool();
        pool.setResolvedCollateral(resolvedAssets, resolvedShares);
        _enableHooks(ActionLib.LC_WITHDRAW_COLLATERAL);
        bytes memory beforeData = abi.encode(user, receiver, user, address(pool), assets, shares);
        bytes memory afterData = abi.encode(user, receiver, user, address(pool), resolvedAssets, resolvedShares);

        _expectBeforeAndAfterHooks(ActionLib.LC_WITHDRAW_COLLATERAL, beforeData, afterData);

        vm.prank(user);
        lendingCore.withdrawCollateral(IPool(address(pool)), assets, shares, user, receiver);
    }

    function testFuzz_withdrawCollateral_ReturnsAmountsResolvedByPool(
        uint256 assets,
        uint256 shares,
        address user,
        address receiver,
        uint256 resolvedAssets,
        uint256 resolvedShares
    ) public {
        assumeNotForgeAddress(user);
        _addPool();
        pool.setResolvedCollateral(resolvedAssets, resolvedShares);

        vm.prank(user);
        (uint256 assetsWithdrawn, uint256 sharesBurned) =
            lendingCore.withdrawCollateral(IPool(address(pool)), assets, shares, user, receiver);

        assertEq(assetsWithdrawn, resolvedAssets);
        assertEq(sharesBurned, resolvedShares);
    }

    function testFuzz_withdrawCollateral_RevertsWhenCallerIsNotAuthorised(
        uint256 assets,
        uint256 shares,
        address caller,
        address onBehalfOf,
        address receiver
    ) public {
        assumeNotForgeAddress(caller);
        vm.assume(caller != onBehalfOf);
        _addPool();

        vm.expectRevert(abi.encodeWithSelector(Authorisable.Unauthorised.selector, onBehalfOf, caller));
        vm.prank(caller);
        lendingCore.withdrawCollateral(IPool(address(pool)), assets, shares, onBehalfOf, receiver);
    }

    // borrow()

    function testFuzz_borrow_ForwardsToPool(uint256 amount, address user, address receiver) public {
        assumeNotForgeAddress(user);
        _addPool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.borrow, (user, amount, receiver)));

        vm.prank(user);
        lendingCore.borrow(IPool(address(pool)), amount, user, receiver);
    }

    function testFuzz_borrow_FiresHooksWithEncodedData(uint256 amount, address user, address receiver) public {
        assumeNotForgeAddress(user);
        _addPool();
        _enableHooks(ActionLib.LC_BORROW);
        bytes memory data = abi.encode(user, receiver, user, address(pool), amount);

        _expectBeforeAndAfterHooks(ActionLib.LC_BORROW, data);

        vm.prank(user);
        lendingCore.borrow(IPool(address(pool)), amount, user, receiver);
    }

    function testFuzz_borrow_RevertsWhenCallerIsNotAuthorised(
        uint256 amount,
        address caller,
        address onBehalfOf,
        address receiver
    ) public {
        assumeNotForgeAddress(caller);
        vm.assume(caller != onBehalfOf);
        _addPool();

        vm.expectRevert(abi.encodeWithSelector(Authorisable.Unauthorised.selector, onBehalfOf, caller));
        vm.prank(caller);
        lendingCore.borrow(IPool(address(pool)), amount, onBehalfOf, receiver);
    }

    // repay()

    function testFuzz_repay_ForwardsToPool(uint256 amount, address user, address onBehalfOf) public {
        assumeNotForgeAddress(user);
        _addPool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.repay, (user, amount, onBehalfOf)));

        vm.prank(user);
        lendingCore.repay(IPool(address(pool)), amount, onBehalfOf);
    }

    function testFuzz_repay_FiresHooksWithEncodedData(
        uint256 amount,
        address user,
        address onBehalfOf,
        uint256 repayment
    ) public {
        assumeNotForgeAddress(user);
        _addPool();
        pool.setRepayment(repayment);
        _enableHooks(ActionLib.LC_REPAY);
        bytes memory beforeData = abi.encode(onBehalfOf, user, user, address(pool), amount);
        bytes memory afterData = abi.encode(onBehalfOf, user, user, address(pool), repayment);

        _expectBeforeAndAfterHooks(ActionLib.LC_REPAY, beforeData, afterData);

        vm.prank(user);
        lendingCore.repay(IPool(address(pool)), amount, onBehalfOf);
    }

    // liquidate()

    function testFuzz_liquidate_ForwardsNonZeroResolvedAmounts(uint256 repayAmount, uint256 seizeAmount) public {
        repayAmount = bound(repayAmount, 1, type(uint256).max);
        seizeAmount = bound(seizeAmount, 1, type(uint256).max);
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        loanEvaluator.setLiquidatable(true);
        _setLiquidation(LoanHelpers.positions(pool, repayAmount), LoanHelpers.positions(pool, seizeAmount));

        vm.expectCall(address(pool), abi.encodeCall(IPool.repay, (liquidator, repayAmount, violator)));
        vm.expectCall(address(pool), abi.encodeCall(IPool.seizeCollateral, (violator, seizeAmount, liquidator)));

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function testFuzz_liquidate_ForwardsAllPositions(uint8 borrowCount, uint8 colCount, uint256 amountSeed) public {
        borrowCount = uint8(bound(borrowCount, 0, 8));
        colCount = uint8(bound(colCount, 0, 8));
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        loanEvaluator.setLiquidatable(true);
        ILendingCore.LoanPosition[] memory bors = new ILendingCore.LoanPosition[](borrowCount);
        for (uint256 i = 0; i < borrowCount; i++) {
            bors[i] = ILendingCore.LoanPosition({
                pool: IPool(address(new MockPool())), amount: uint256(keccak256(abi.encode(amountSeed, "borrow", i)))
            });
        }
        ILendingCore.LoanPosition[] memory cols = new ILendingCore.LoanPosition[](colCount);
        for (uint256 i = 0; i < colCount; i++) {
            cols[i] = ILendingCore.LoanPosition({
                pool: IPool(address(new MockPool())),
                amount: uint256(keccak256(abi.encode(amountSeed, "collateral", i)))
            });
        }
        _setLiquidation(bors, cols);

        for (uint256 i = 0; i < borrowCount; i++) {
            vm.expectCall(address(bors[i].pool), abi.encodeCall(IPool.repay, (liquidator, bors[i].amount, violator)), 1);
        }
        for (uint256 i = 0; i < colCount; i++) {
            vm.expectCall(
                address(cols[i].pool), abi.encodeCall(IPool.seizeCollateral, (violator, cols[i].amount, liquidator)), 1
            );
        }

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function testFuzz_liquidate_FiresHooksWithEncodedData(
        address liquidator,
        address violator,
        uint256 reqColAmount,
        uint256 reqBorAmount
    ) public {
        assumeNotForgeAddress(liquidator);
        loanEvaluator.setLiquidatable(true);
        ILendingCore.LoanPosition[] memory reqCols = LoanHelpers.positions(pool, reqColAmount);
        ILendingCore.LoanPosition[] memory reqBors = LoanHelpers.positions(pool, reqBorAmount);
        _enableHooks(ActionLib.LC_LIQUIDATE);
        bytes memory beforeData = abi.encode(violator, liquidator, liquidator, reqCols, reqBors);
        bytes memory afterData = abi.encode(
            violator,
            liquidator,
            liquidator,
            LoanHelpers.noPositions(),
            LoanHelpers.noPositions(),
            LoanHelpers.noPositions()
        );

        _expectBeforeAndAfterHooks(ActionLib.LC_LIQUIDATE, beforeData, afterData);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, reqCols, reqBors);
    }

    function testFuzz_liquidate_WritesOffDebtInEveryPoolThatCarriesItWhenNoCollateralRemains(
        uint256 poolCount,
        uint8 debtZeroMask,
        uint256 debtAmount
    ) public {
        // One bit per borrow pool in the `uint8` zero mask.
        poolCount = bound(poolCount, 1, 8);
        debtAmount = bound(debtAmount, 1, type(uint128).max);
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        _addPool();
        MockPool[] memory borrowPools = _addPools(poolCount);
        _enableBadDebtSocialisation();
        loanEvaluator.setLiquidatable(true);
        pool.setCollateralOf(violator, 100e18);
        pool.setCollateralOfAfterSeize(violator, 0);
        for (uint256 i; i < poolCount; ++i) {
            if (!_isZero(debtZeroMask, i)) borrowPools[i].setDebtOf(violator, debtAmount + i);
        }
        _setLiquidation(LoanHelpers.noPositions(), LoanHelpers.positions(pool, 100e18));

        for (uint256 i; i < poolCount; ++i) {
            uint64 expectedCalls = _isZero(debtZeroMask, i) ? 0 : 1;
            vm.expectCall(address(borrowPools[i]), abi.encodeCall(IPool.writeOffDebt, (violator)), expectedCalls);
        }

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function testFuzz_liquidate_DoesNotWriteOffDebtWhenCollateralRemains(uint256 remainingCollateral, uint256 debt)
        public
    {
        remainingCollateral = bound(remainingCollateral, 1, type(uint256).max);
        debt = bound(debt, 1, type(uint256).max);
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        _addPool();
        _enableBadDebtSocialisation();
        loanEvaluator.setLiquidatable(true);
        pool.setCollateralOf(violator, 100e18);
        pool.setDebtOf(violator, debt);
        pool.setCollateralOfAfterSeize(violator, remainingCollateral);
        _setLiquidation(LoanHelpers.noPositions(), LoanHelpers.positions(pool, 1));

        vm.expectCall(address(pool), abi.encodeCall(IPool.writeOffDebt, (violator)), 0);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    // loanOf()

    function testFuzz_loanOf_IncludesExactlyTheNonZeroPositions(
        address account,
        uint256 poolCount,
        uint8 collateralZeroMask,
        uint8 debtZeroMask,
        uint256 collateralAmount,
        uint256 debtAmount
    ) public {
        // One bit per pool in each of the `uint8` zero masks.
        poolCount = bound(poolCount, 0, 8);
        collateralAmount = bound(collateralAmount, 1, type(uint128).max);
        debtAmount = bound(debtAmount, 1, type(uint128).max);
        MockPool[] memory listed = _addPools(poolCount);
        for (uint256 i; i < poolCount; ++i) {
            if (!_isZero(collateralZeroMask, i)) listed[i].setCollateralOf(account, collateralAmount + i);
            if (!_isZero(debtZeroMask, i)) listed[i].setDebtOf(account, debtAmount + i);
        }

        ILendingCore.Loan memory loan = lendingCore.loanOf(account);

        assertEq(loan.account, account);
        uint256 collateralCount;
        uint256 borrowCount;
        for (uint256 i; i < poolCount; ++i) {
            if (!_isZero(collateralZeroMask, i)) {
                assertEq(address(loan.collaterals[collateralCount].pool), address(listed[i]));
                assertEq(loan.collaterals[collateralCount].amount, collateralAmount + i);
                ++collateralCount;
            }
            if (!_isZero(debtZeroMask, i)) {
                assertEq(address(loan.borrows[borrowCount].pool), address(listed[i]));
                assertEq(loan.borrows[borrowCount].amount, debtAmount + i);
                ++borrowCount;
            }
        }
        assertEq(loan.collaterals.length, collateralCount);
        assertEq(loan.borrows.length, borrowCount);
    }

    function _addPool() internal {
        vm.prank(poolLister);
        lendingCore.addPool(address(pool));
    }

    /// @dev Deploys and lists `count` fresh pools as `poolLister`, returned in listing order.
    function _addPools(uint256 count) internal returns (MockPool[] memory listed) {
        listed = new MockPool[](count);
        for (uint256 i; i < count; ++i) {
            listed[i] = new MockPool();
        }
        vm.startPrank(poolLister);
        for (uint256 i; i < count; ++i) {
            lendingCore.addPool(address(listed[i]));
        }
        vm.stopPrank();
    }

    function _enableBadDebtSocialisation() internal {
        vm.prank(badDebtConfigurator);
        lendingCore.setSocialiseBadDebt(true);
    }

    /// @dev Whether bit `bit` of `mask` is set, marking that slot as zero.
    function _isZero(uint8 mask, uint256 bit) internal pure returns (bool) {
        return (mask >> bit) & 1 == 1;
    }

    /// @dev Configures the liquidation engine to return the given borrows to repay and collateral to seize.
    function _setLiquidation(ILendingCore.LoanPosition[] memory bors, ILendingCore.LoanPosition[] memory cols)
        internal
    {
        liquidationEngine.setBorsToRepay(bors);
        liquidationEngine.setColsToSeize(cols);
    }

    /// @dev Sets `hookReceiver` and enables `action`'s before and after hook bits.
    function _enableHooks(uint8 action) internal {
        uint256 bitmap = uint256(1) << action;
        vm.startPrank(hookUpdater);
        lendingCore.setHookReceiver(address(hookReceiver));
        lendingCore.setHookBitmaps(bitmap, bitmap);
        vm.stopPrank();
    }

    /// @dev Expects the before and after `HookCalled` events from `lendingCore` for `action` with `data`, in order.
    function _expectBeforeAndAfterHooks(uint8 action, bytes memory data) internal {
        _expectBeforeAndAfterHooks(action, data, data);
    }

    function _expectBeforeAndAfterHooks(uint8 action, bytes memory beforeData, bytes memory afterData) internal {
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(address(lendingCore), Phase.BEFORE, action, beforeData);
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(address(lendingCore), Phase.AFTER, action, afterData);
    }
}
