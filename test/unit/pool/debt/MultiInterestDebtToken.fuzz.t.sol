// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {MultiInterestDebtToken} from "src/pool/debt/MultiInterestDebtToken.sol";
import {MockIrm} from "../irm/mocks/MockIrm.sol";
import {MultiInterestDebtTokenHarness} from "./mocks/MultiInterestDebtTokenHarness.sol";

contract MultiInterestDebtTokenFuzzTest is Test {
    uint256 constant MAX_ELAPSED = 100 * 365 days;
    // Minimum annual 18dp rate whose per-second rate does not round to zero: 1 * seconds per year.
    uint256 constant MIN_ACCRUING_BORROW_RATE = MathUtils.SECONDS_IN_YEAR;
    uint256 constant IDLE_LIQUIDITY = 5000e18;

    // Bounds chosen so index/debt math stays within uint256 across the fuzzed elapsed window.
    uint256 constant MAX_BORROW_RATE = 10e18; // 1000% APR
    uint256 constant MAX_RETENTION_RATE = 1e18; // 100%
    uint256 constant MAX_AMOUNT = 1e30;
    uint256 constant MAX_ACCRUAL_ELAPSED = 10 * 365 days;

    MultiInterestDebtTokenHarness debtToken;
    MockIrm firstIrm;
    MockIrm secondIrm;
    MockIrm thirdIrm;
    MockIrm insertedIrm;

    address pool = makeAddr("pool");
    address irmUpdater = makeAddr("irmUpdater");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    string constant NAME = "dOnlend USD Coin";
    string constant SYMBOL = "dOnlend USDC";
    uint8 constant DECIMALS = 6;

    function setUp() public {
        MultiInterestDebtTokenHarness implementation = new MultiInterestDebtTokenHarness();
        debtToken = MultiInterestDebtTokenHarness(Clones.clone(address(implementation)));
        debtToken.initialize(pool, NAME, SYMBOL, DECIMALS, makeAddr("defaultAdmin"), irmUpdater, new address[](0));
        firstIrm = new MockIrm(true, 0, 0);
        secondIrm = new MockIrm(true, 0, 0);
        thirdIrm = new MockIrm(true, 0, 0);
        insertedIrm = new MockIrm(true, 0, 0);
    }

    // addIrm()

    function testFuzz_addIrm_InsertsIrmAtPriority(uint8 priority) public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
        priority = uint8(bound(priority, 0, 3));

        _addIrm(insertedIrm, priority);

        assertEq(debtToken.getActiveIrmIds(), _expectedIrmIdsAfterInsert(priority));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
    }

    function testFuzz_addIrm_RevertsWhenPriorityIsGreaterThanActiveIrmCount(uint8 priority) public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
        priority = uint8(bound(priority, 4, type(uint8).max));

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.InvalidIrmPriority.selector, priority));
        vm.prank(irmUpdater);
        debtToken.addIrm(address(insertedIrm), priority);

        assertEq(debtToken.getActiveIrmIds(), _addedIrmIds());
        assertEq(debtToken.getSupportedIrmIds(), _addedIrmIds());
    }

    // deprecateIrm()

    function testFuzz_deprecateIrm_MovesActiveIrmAtIndexToDeprecatedIrms(uint8 index) public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
        index = uint8(bound(index, 0, 2));
        address deprecatedIrm = _irmIdAt(index);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(deprecatedIrm);

        assertEq(debtToken.getActiveIrmIds(), _addedIrmIdsWithout(index));
        assertEq(debtToken.getDeprecatedIrmIds(), _singleIrmId(deprecatedIrm));
        assertEq(debtToken.getSupportedIrmIds(), _addedIrmIds());
        assertEq(uint8(debtToken.getIrmData(deprecatedIrm).status), uint8(MultiInterestDebtToken.IrmStatus.DEPRECATED));
    }

    // undeprecateIrm()

    function testFuzz_undeprecateIrm_MovesDeprecatedIrmToActiveAtPriority(uint8 index, uint8 priority) public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
        index = uint8(bound(index, 0, 2));
        priority = uint8(bound(priority, 0, 2));
        address deprecatedIrm = _irmIdAt(index);

        vm.startPrank(irmUpdater);
        debtToken.deprecateIrm(deprecatedIrm);
        debtToken.undeprecateIrm(deprecatedIrm, priority);
        vm.stopPrank();

        address[] memory expectedActiveIrmIds = _expectedActiveIrmIdsAfterUndeprecate(index, priority);
        assertEq(debtToken.getActiveIrmIds(), expectedActiveIrmIds);
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _addedIrmIds());
        assertEq(uint8(debtToken.getIrmData(deprecatedIrm).status), uint8(MultiInterestDebtToken.IrmStatus.ACTIVE));
    }

    function testFuzz_undeprecateIrm_RevertsWhenPriorityIsGreaterThanActiveIrmCount(uint8 index, uint8 priority)
        public
    {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
        index = uint8(bound(index, 0, 2));
        priority = uint8(bound(priority, 3, type(uint8).max));
        address deprecatedIrm = _irmIdAt(index);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(deprecatedIrm);

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.InvalidIrmPriority.selector, priority));
        vm.prank(irmUpdater);
        debtToken.undeprecateIrm(deprecatedIrm, priority);

        assertEq(debtToken.getActiveIrmIds(), _addedIrmIdsWithout(index));
        assertEq(debtToken.getDeprecatedIrmIds(), _singleIrmId(deprecatedIrm));
    }

    // removeIrm()

    function testFuzz_removeIrm_RemovesActiveIrmAtIndex(uint8 index) public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
        index = uint8(bound(index, 0, 2));
        address removedIrm = _irmIdAt(index);

        vm.prank(irmUpdater);
        debtToken.removeIrm(removedIrm);

        assertEq(debtToken.getActiveIrmIds(), _addedIrmIdsWithout(index));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _addedIrmIdsWithout(index));
        assertFalse(debtToken.isIrmSupported(removedIrm));
    }

    function testFuzz_removeIrm_RemovesDeprecatedIrmAtIndex(uint8 index) public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
        index = uint8(bound(index, 0, 2));
        address removedIrm = _irmIdAt(index);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(removedIrm);

        vm.prank(irmUpdater);
        debtToken.removeIrm(removedIrm);

        assertEq(debtToken.getActiveIrmIds(), _addedIrmIdsWithout(index));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _addedIrmIdsWithout(index));
        assertFalse(debtToken.isIrmSupported(removedIrm));
    }

    function testFuzz_removeIrm_RevertsWhenIrmHasDebt(uint256 totalScaledDebt) public {
        _addIrm(firstIrm, 0);
        totalScaledDebt = bound(totalScaledDebt, 1, type(uint256).max);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), totalScaledDebt);

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmHasDebt.selector, address(firstIrm)));
        vm.prank(irmUpdater);
        debtToken.removeIrm(address(firstIrm));
    }

    // setIrmPriorities()

    function testFuzz_setIrmPriorities_ReordersActiveIrms(uint8 permutation) public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
        permutation = uint8(bound(permutation, 0, 5));
        address[] memory newPriorities = _irmPriorityPermutation(permutation);

        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(newPriorities);

        assertEq(debtToken.getActiveIrmIds(), newPriorities);
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _addedIrmIds());
    }

    function testFuzz_setIrmPriorities_RevertsWhenAnyIrmIsDuplicated(uint8 duplicated, uint8 displaced) public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
        duplicated = uint8(bound(duplicated, 0, 2));
        displaced = uint8(bound(displaced, 0, 1));
        address[] memory newPriorities = _addedIrmIds();
        // Overwrite one of the two positions the duplicated IRM does not already occupy, keeping the length valid.
        newPriorities[(duplicated + 1 + displaced) % 3] = _irmIdAt(duplicated);

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.DuplicateIrm.selector, _irmIdAt(duplicated)));
        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(newPriorities);

        assertEq(debtToken.getActiveIrmIds(), _addedIrmIds());
        assertEq(debtToken.getSupportedIrmIds(), _addedIrmIds());
    }

    // pendingInterest()

    function testFuzz_pendingInterest_DoesNotAccrueWhenDebtIsZero(
        uint256 storedBorrowIndex,
        uint256 borrowRate,
        uint256 retentionRate,
        uint256 elapsed
    ) public {
        storedBorrowIndex = bound(storedBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MathUtils.ONE_18_DP);
        retentionRate = bound(retentionRate, MathUtils.ONE_18_DP / 100, MathUtils.ONE_18_DP);
        elapsed = bound(elapsed, 1 days, 365 days);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        debtToken.setIrmRetentionRate(address(firstIrm), retentionRate);
        vm.warp(lastUpdateTs + elapsed);

        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();

        assertEq(accrued, 0);
        assertEq(retained, 0);
    }

    function testFuzz_pendingInterest_DoesNotRetainWhenRetentionRateIsZero(
        uint256 amount,
        uint256 storedBorrowIndex,
        uint256 borrowRate,
        uint256 elapsed
    ) public {
        amount = bound(amount, MathUtils.ONE_18_DP, type(uint128).max);
        storedBorrowIndex = bound(storedBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MathUtils.ONE_18_DP);
        elapsed = bound(elapsed, 1 days, 365 days);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.warp(lastUpdateTs + elapsed);

        (, uint256 retained) = debtToken.pendingInterest();

        assertEq(retained, 0);
    }

    function testFuzz_pendingInterest_AccruesGrowthInDebt(
        uint256 amount,
        uint256 storedBorrowIndex,
        uint256 borrowRate,
        uint256 retentionRate,
        uint256 elapsed
    ) public {
        amount = bound(amount, MathUtils.ONE_18_DP, type(uint128).max);
        storedBorrowIndex = bound(storedBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MathUtils.ONE_18_DP);
        retentionRate = bound(retentionRate, 0, MAX_RETENTION_RATE);
        elapsed = bound(elapsed, 1 days, 365 days);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        debtToken.setIrmRetentionRate(address(firstIrm), retentionRate);
        uint256 totalDebtBeforeAccrual = debtToken.updatedTotalDebt(address(firstIrm));
        vm.warp(lastUpdateTs + elapsed);

        (uint256 accrued,) = debtToken.pendingInterest();

        assertEq(accrued, debtToken.updatedTotalDebt(address(firstIrm)) - totalDebtBeforeAccrual);
        assertGt(accrued, 0);
    }

    function testFuzz_pendingInterest_RetainsAllAccruedInterestWhenRetentionRateIsFull(
        uint256 amount,
        uint256 storedBorrowIndex,
        uint256 borrowRate,
        uint256 elapsed
    ) public {
        amount = bound(amount, MathUtils.ONE_18_DP, type(uint128).max);
        storedBorrowIndex = bound(storedBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MathUtils.ONE_18_DP);
        elapsed = bound(elapsed, 1 days, 365 days);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        debtToken.setIrmRetentionRate(address(firstIrm), MathUtils.ONE_18_DP);
        vm.warp(lastUpdateTs + elapsed);

        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();

        assertEq(retained, accrued);
        assertGt(retained, 0);
    }

    function testFuzz_pendingInterest_RetainsShareOfAccruedInterest(
        uint256 amount,
        uint256 storedBorrowIndex,
        uint256 borrowRate,
        uint256 retentionRate,
        uint256 elapsed
    ) public {
        amount = bound(amount, MathUtils.ONE_18_DP, type(uint128).max);
        storedBorrowIndex = bound(storedBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MathUtils.ONE_18_DP);
        retentionRate = bound(retentionRate, MathUtils.ONE_18_DP / 100, MathUtils.ONE_18_DP);
        elapsed = bound(elapsed, 1 days, 365 days);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        debtToken.setIrmRetentionRate(address(firstIrm), retentionRate);
        vm.warp(lastUpdateTs + elapsed);

        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();

        assertLe(retained, accrued);
        assertGt(retained, 0);
    }

    function testFuzz_pendingInterest_RetainedNonDecreasingInRetentionRate(
        uint256 amount,
        uint256 borrowRate,
        uint256 lowRetention,
        uint256 highRetention,
        uint256 elapsed
    ) public {
        amount = bound(amount, MathUtils.ONE_18_DP, type(uint128).max);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MathUtils.ONE_18_DP);
        lowRetention = bound(lowRetention, 0, MAX_RETENTION_RATE);
        highRetention = bound(highRetention, lowRetention, MAX_RETENTION_RATE);
        elapsed = bound(elapsed, 1 days, 365 days);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.warp(lastUpdateTs + elapsed);
        debtToken.setIrmRetentionRate(address(firstIrm), lowRetention);
        (, uint256 retainedAtLowRate) = debtToken.pendingInterest();

        debtToken.setIrmRetentionRate(address(firstIrm), highRetention);

        (, uint256 retainedAtHighRate) = debtToken.pendingInterest();
        assertGe(retainedAtHighRate, retainedAtLowRate);
    }

    // annualInterest()

    function testFuzz_annualInterest_RetainedNeverExceedsInterest(
        uint256 amount,
        uint256 borrowRate,
        uint256 retentionRate
    ) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        retentionRate = bound(retentionRate, 0, MAX_RETENTION_RATE);
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, borrowRate, retentionRate);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);

        (uint256 interest, uint256 retained) = debtToken.annualInterest();

        assertLe(retained, interest);
    }

    /// @dev The retention rate decides only how the interest is divided, never how much of it there is.
    function testFuzz_annualInterest_InterestIsIndependentOfRetentionRate(
        uint256 amount,
        uint256 borrowRate,
        uint256 retentionRate
    ) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        retentionRate = bound(retentionRate, 0, MAX_RETENTION_RATE);
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, borrowRate, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        (uint256 interestWithoutRetention,) = debtToken.annualInterest();

        debtToken.setIrmRetentionRate(address(firstIrm), retentionRate);

        (uint256 interest,) = debtToken.annualInterest();
        assertEq(interest, interestWithoutRetention);
    }

    function testFuzz_annualInterest_RetainsNothingWhenRetentionZero(uint256 amount, uint256 borrowRate) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, borrowRate, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);

        (, uint256 retained) = debtToken.annualInterest();

        assertEq(retained, 0);
    }

    function testFuzz_annualInterest_RetainsAllInterestWhenRetentionFull(uint256 amount, uint256 borrowRate) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, borrowRate, MathUtils.ONE_18_DP);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);

        (uint256 interest, uint256 retained) = debtToken.annualInterest();

        assertEq(retained, interest);
    }

    /// @dev Raising the retention rate can only increase (never reduce) the retained part, holding debt and borrow
    ///      rate fixed. Asserts the direction of retention's effect without recomputing it.
    function testFuzz_annualInterest_RetainedIsNonDecreasingInRetention(
        uint256 amount,
        uint256 borrowRate,
        uint256 lowRetention,
        uint256 highRetention
    ) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        borrowRate = bound(borrowRate, 1, MAX_BORROW_RATE);
        lowRetention = bound(lowRetention, 0, MAX_RETENTION_RATE);
        highRetention = bound(highRetention, lowRetention, MAX_RETENTION_RATE);
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, borrowRate, lowRetention);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        (, uint256 retainedAtLowRetention) = debtToken.annualInterest();

        debtToken.setIrmRetentionRate(address(firstIrm), highRetention);

        (, uint256 retainedAtHighRetention) = debtToken.annualInterest();
        assertGe(retainedAtHighRetention, retainedAtLowRetention);
    }

    /// @dev Total interest is the sum of the per-IRM contributions across both the active and deprecated lists. Each
    ///      contribution is isolated by zeroing the other IRM's borrow rate, so the assertion checks additivity over
    ///      the two lists rather than reconstructing the per-IRM formula.
    function testFuzz_annualInterest_SumsActiveAndDeprecatedContributions(
        uint256 activeAmount,
        uint256 activeBorrowRate,
        uint256 activeRetentionRate,
        uint256 deprecatedAmount,
        uint256 deprecatedBorrowRate,
        uint256 deprecatedRetentionRate
    ) public {
        activeAmount = bound(activeAmount, 0, MAX_AMOUNT);
        activeBorrowRate = bound(activeBorrowRate, 0, MAX_BORROW_RATE);
        activeRetentionRate = bound(activeRetentionRate, 0, MAX_RETENTION_RATE);
        deprecatedAmount = bound(deprecatedAmount, 0, MAX_AMOUNT);
        deprecatedBorrowRate = bound(deprecatedBorrowRate, 0, MAX_BORROW_RATE);
        deprecatedRetentionRate = bound(deprecatedRetentionRate, 0, MAX_RETENTION_RATE);
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), deprecatedAmount);
        debtToken.setIrmTotalScaledDebt(address(secondIrm), activeAmount);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        _setIrmRates(firstIrm, deprecatedBorrowRate, deprecatedRetentionRate);
        _setIrmRates(secondIrm, 0, activeRetentionRate);
        (uint256 deprecatedInterest, uint256 deprecatedRetained) = debtToken.annualInterest();
        _setIrmRates(firstIrm, 0, deprecatedRetentionRate);
        _setIrmRates(secondIrm, activeBorrowRate, activeRetentionRate);
        (uint256 activeInterest, uint256 activeRetained) = debtToken.annualInterest();

        debtToken.setIrmBorrowRate(address(firstIrm), deprecatedBorrowRate);

        (uint256 interest, uint256 retained) = debtToken.annualInterest();
        assertEq(interest, deprecatedInterest + activeInterest);
        assertEq(retained, deprecatedRetained + activeRetained);
    }

    /// @dev Debt is stated at the index the current block would produce, so accruing that same growth into storage
    ///      leaves the interest where it was — an exact identity across the accrual boundary that reproduces none of
    ///      the arithmetic.
    function testFuzz_annualInterest_IsUnchangedByAccruingInterest(
        uint256 amount,
        uint256 storedBorrowIndex,
        uint256 borrowRate,
        uint256 retentionRate,
        uint256 elapsed
    ) public {
        amount = bound(amount, MathUtils.ONE_18_DP, type(uint128).max);
        storedBorrowIndex = bound(storedBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MathUtils.ONE_18_DP);
        retentionRate = bound(retentionRate, 0, MAX_RETENTION_RATE);
        elapsed = bound(elapsed, 1 days, 365 days);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, borrowRate, retentionRate);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        vm.warp(lastUpdateTs + elapsed);
        (uint256 interestBeforeAccrual, uint256 retainedBeforeAccrual) = debtToken.annualInterest();

        vm.prank(pool);
        debtToken.accrueInterest();

        (uint256 interest, uint256 retained) = debtToken.annualInterest();
        assertEq(interest, interestBeforeAccrual);
        assertEq(retained, retainedBeforeAccrual);
    }

    // getSupportedIrmIds()

    function testFuzz_getSupportedIrmIds_PartitionsIntoActiveAndDeprecatedIrms(
        uint8 secondPriority,
        uint8 thirdPriority,
        uint8 deprecationMask
    ) public {
        secondPriority = uint8(bound(secondPriority, 0, 1));
        thirdPriority = uint8(bound(thirdPriority, 0, 2));
        deprecationMask = uint8(bound(deprecationMask, 0, 7));
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, secondPriority);
        _addIrm(thirdIrm, thirdPriority);

        for (uint8 i; i < 3; i++) {
            if (deprecationMask & (uint256(1) << i) == 0) continue;
            vm.prank(irmUpdater);
            debtToken.deprecateIrm(_irmIdAt(i));
        }

        address[] memory supportedIrmIds = debtToken.getSupportedIrmIds();
        uint256 activeCount = debtToken.getActiveIrmIds().length;
        uint256 deprecatedCount = debtToken.getDeprecatedIrmIds().length;
        assertEq(supportedIrmIds, _addedIrmIds());
        assertEq(activeCount + deprecatedCount, supportedIrmIds.length);
        for (uint8 i; i < 3; i++) {
            MultiInterestDebtToken.IrmStatus expectedStatus = deprecationMask & (uint256(1) << i) == 0
                ? MultiInterestDebtToken.IrmStatus.ACTIVE
                : MultiInterestDebtToken.IrmStatus.DEPRECATED;
            assertEq(uint8(debtToken.getIrmData(supportedIrmIds[i]).status), uint8(expectedStatus));
        }
    }

    // findIrmForAccount()

    function testFuzz_findIrmForAccount_ReturnsHighestPriorityApplicableIrm(uint8 applicableIndex) public {
        applicableIndex = uint8(bound(applicableIndex, 0, 2));
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
        firstIrm.setIsApplicable(applicableIndex == 0);
        secondIrm.setIsApplicable(applicableIndex <= 1);

        assertEq(debtToken.findIrmForAccount(bob), _irmIdAt(applicableIndex));
    }

    function testFuzz_findIrmForAccount_RevertsWhenNoActiveIrmIsApplicable(uint8 count) public {
        count = uint8(bound(count, 1, 3));
        for (uint8 i; i < count; i++) {
            _addIrm(MockIrm(_irmIdAt(i)), i);
            MockIrm(_irmIdAt(i)).setIsApplicable(false);
        }

        vm.expectRevert(MultiInterestDebtToken.NoApplicableIrmFound.selector);
        debtToken.findIrmForAccount(bob);
    }

    // balanceOf()

    function testFuzz_balanceOf_ReturnsZeroWhenAccountHasNoDebt(address account) public {
        _addIrm(firstIrm, 0);

        assertEq(debtToken.balanceOf(account), 0);
    }

    function testFuzz_balanceOf_AccruesToIrmTotalDebtForSoleBorrower(
        uint256 amount,
        uint256 borrowRate,
        uint256 elapsed
    ) public {
        amount = bound(amount, MathUtils.ONE_18_DP, MAX_AMOUNT);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MAX_BORROW_RATE);
        elapsed = bound(elapsed, 1 days, MAX_ACCRUAL_ELAPSED);
        _addIrm(firstIrm, 0);
        _mint(bob, amount);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.warp(debtToken.lastUpdateTs() + elapsed);

        uint256 balance = debtToken.balanceOf(bob);

        assertEq(balance, debtToken.updatedTotalDebt(address(firstIrm)));
        assertGt(balance, amount);
    }

    function testFuzz_balanceOf_DoesNotAccrueWhenBorrowRateIsZero(uint256 amount, uint256 elapsed) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        _addIrm(firstIrm, 0);
        _mint(bob, amount);
        vm.warp(debtToken.lastUpdateTs() + elapsed);

        assertEq(debtToken.balanceOf(bob), amount);
    }

    // totalSupply()

    function testFuzz_totalSupply_SumsAcrossActiveAndDeprecatedIrms(
        uint256 firstAmount,
        uint256 secondAmount,
        uint256 borrowRate,
        uint256 elapsed
    ) public {
        firstAmount = bound(firstAmount, MathUtils.ONE_18_DP, type(uint128).max);
        secondAmount = bound(secondAmount, MathUtils.ONE_18_DP, type(uint128).max);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MathUtils.ONE_18_DP);
        elapsed = bound(elapsed, 1 days, 365 days);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), firstAmount);
        debtToken.setIrmTotalScaledDebt(address(secondIrm), secondAmount);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        vm.warp(lastUpdateTs + elapsed);

        uint256 totalSupply = debtToken.totalSupply();

        assertEq(
            totalSupply, debtToken.updatedTotalDebt(address(firstIrm)) + debtToken.updatedTotalDebt(address(secondIrm))
        );
        assertGt(totalSupply, firstAmount + secondAmount);
    }

    // updatedBorrowIndex()

    function testFuzz_updatedBorrowIndex_DoesNotAccrueWhenBorrowRateIsZero(uint256 storedBorrowIndex, uint256 elapsed)
        public
    {
        storedBorrowIndex = bound(storedBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        _addIrm(firstIrm, 0);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        vm.warp(block.timestamp + elapsed);

        assertEq(debtToken.updatedBorrowIndex(address(firstIrm)), storedBorrowIndex);
    }

    function testFuzz_updatedBorrowIndex_DoesNotAccrueWhenBorrowRatePerSecondRoundsToZero(
        uint256 storedBorrowIndex,
        uint256 borrowRate,
        uint256 elapsed
    ) public {
        storedBorrowIndex = bound(storedBorrowIndex, 1, type(uint128).max);
        borrowRate = bound(borrowRate, 1, MIN_ACCRUING_BORROW_RATE - 1);
        elapsed = bound(elapsed, 1, MAX_ELAPSED);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.warp(lastUpdateTs + elapsed);

        assertEq(debtToken.updatedBorrowIndex(address(firstIrm)), storedBorrowIndex);
    }

    function testFuzz_updatedBorrowIndex_DoesNotAccrueWhenNoTimeHasElapsed(
        uint256 storedBorrowIndex,
        uint256 borrowRate
    ) public {
        storedBorrowIndex = bound(storedBorrowIndex, 1, type(uint128).max);
        borrowRate = bound(borrowRate, 0, MathUtils.ONE_18_DP);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.warp(lastUpdateTs);

        assertEq(debtToken.updatedBorrowIndex(address(firstIrm)), storedBorrowIndex);
    }

    function testFuzz_updatedBorrowIndex_AccruesBorrowIndex(
        uint256 storedBorrowIndex,
        uint256 borrowRate,
        uint256 elapsed
    ) public {
        storedBorrowIndex = bound(storedBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MathUtils.ONE_18_DP);
        elapsed = bound(elapsed, 1, 365 days);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.warp(lastUpdateTs + elapsed);

        uint256 updatedBorrowIndex = debtToken.updatedBorrowIndex(address(firstIrm));

        assertGt(updatedBorrowIndex, storedBorrowIndex);
    }

    function testFuzz_updatedBorrowIndex_AccruesOverLongPeriods(
        uint256 storedBorrowIndex,
        uint256 borrowRate,
        uint256 elapsed
    ) public {
        storedBorrowIndex = bound(storedBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, 0.1e18);
        elapsed = bound(elapsed, 365 days + 1, MAX_ELAPSED);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.warp(lastUpdateTs + elapsed);

        assertGt(debtToken.updatedBorrowIndex(address(firstIrm)), storedBorrowIndex);
    }

    // updatedTotalDebt()

    function testFuzz_updatedTotalDebt_DoesNotAccrueWhenBorrowIndexIsSame(
        uint256 amount,
        uint256 storedBorrowIndex,
        uint256 elapsed
    ) public {
        amount = bound(amount, 0, type(uint128).max);
        storedBorrowIndex = bound(storedBorrowIndex, 1, type(uint128).max);
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        uint256 totalDebtBeforeWarp = debtToken.updatedTotalDebt(address(firstIrm));
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        vm.warp(block.timestamp + elapsed);

        assertEq(debtToken.updatedTotalDebt(address(firstIrm)), totalDebtBeforeWarp);
    }

    function testFuzz_updatedTotalDebt_AccruesDebt(
        uint256 amount,
        uint256 storedBorrowIndex,
        uint256 borrowRate,
        uint256 elapsed
    ) public {
        amount = bound(amount, MathUtils.ONE_18_DP, type(uint128).max);
        storedBorrowIndex = bound(storedBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MathUtils.ONE_18_DP);
        elapsed = bound(elapsed, 1 days, 365 days);
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), storedBorrowIndex);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        uint256 totalDebtBeforeAccrual = debtToken.updatedTotalDebt(address(firstIrm));
        vm.warp(lastUpdateTs + elapsed);

        assertGt(debtToken.updatedTotalDebt(address(firstIrm)), totalDebtBeforeAccrual);
    }

    function testFuzz_updatedTotalDebt_DoublesWhenBorrowIndexDoubles(uint256 amount) public {
        amount = bound(amount, 0, type(uint128).max);
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        debtToken.setIrmTotalScaledDebt(address(secondIrm), amount);
        debtToken.setIrmStoredBorrowIndex(address(secondIrm), 2 * MathUtils.ONE_18_DP);

        assertEq(debtToken.updatedTotalDebt(address(secondIrm)), 2 * debtToken.updatedTotalDebt(address(firstIrm)));
    }

    // syncAccount()

    function testFuzz_syncAccount_NeverReducesDebtOnReassignment(
        uint256 amount,
        uint256 oldStoredBorrowIndex,
        uint256 newStoredBorrowIndex
    ) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        oldStoredBorrowIndex = bound(oldStoredBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        newStoredBorrowIndex = bound(newStoredBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), oldStoredBorrowIndex);
        _mint(bob, amount);
        debtToken.setIrmStoredBorrowIndex(address(secondIrm), newStoredBorrowIndex);
        uint256 debtBefore = debtToken.balanceOf(bob);

        _syncAccountTo(bob, secondIrm);

        assertGe(debtToken.balanceOf(bob), debtBefore);
    }

    function testFuzz_syncAccount_MovesWholePositionBetweenBuckets(
        uint256 amount,
        uint256 oldStoredBorrowIndex,
        uint256 newStoredBorrowIndex
    ) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        oldStoredBorrowIndex = bound(oldStoredBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        newStoredBorrowIndex = bound(newStoredBorrowIndex, MathUtils.ONE_18_DP, type(uint128).max);
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), oldStoredBorrowIndex);
        _mint(bob, amount);
        debtToken.setIrmStoredBorrowIndex(address(secondIrm), newStoredBorrowIndex);

        _syncAccountTo(bob, secondIrm);

        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, 0);
        assertEq(debtToken.getIrmData(address(secondIrm)).totalScaledDebt, debtToken.scaledBalanceOf(bob));
    }

    // accrueInterest()

    function testFuzz_accrueInterest_WritesPreviewedValues(
        uint256 borrowRate,
        uint256 retentionRate,
        uint256 amount,
        uint256 elapsed
    ) public {
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        retentionRate = bound(retentionRate, 0, MAX_RETENTION_RATE);
        amount = bound(amount, 1, MAX_AMOUNT);
        elapsed = bound(elapsed, 0, MAX_ACCRUAL_ELAPSED);
        _addIrm(firstIrm, 0);
        _mint(bob, amount);
        _setIrmRates(firstIrm, borrowRate, retentionRate);
        vm.warp(block.timestamp + elapsed);
        uint256 expectedIndex = debtToken.updatedBorrowIndex(address(firstIrm));
        uint256 expectedDebt = debtToken.updatedTotalDebt(address(firstIrm));
        (uint256 expectedAccrued, uint256 expectedRetained) = debtToken.pendingInterest();

        vm.prank(pool);
        (uint256 accrued, uint256 retained) = debtToken.accrueInterest();

        assertEq(debtToken.getIrmData(address(firstIrm)).storedBorrowIndex, expectedIndex);
        assertEq(debtToken.updatedTotalDebt(address(firstIrm)), expectedDebt);
        assertEq(accrued, expectedAccrued);
        assertEq(retained, expectedRetained);
        assertEq(debtToken.lastUpdateTs(), block.timestamp);
    }

    /// @dev Interest is handed to the caller rather than stored, so nothing is left pending once it is returned.
    function testFuzz_accrueInterest_ClearsPendingInterest(
        uint256 borrowRate,
        uint256 retentionRate,
        uint256 amount,
        uint256 elapsed
    ) public {
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        retentionRate = bound(retentionRate, 0, MAX_RETENTION_RATE);
        amount = bound(amount, 1, MAX_AMOUNT);
        elapsed = bound(elapsed, 0, MAX_ACCRUAL_ELAPSED);
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        _setIrmRates(firstIrm, borrowRate, retentionRate);
        vm.warp(block.timestamp + elapsed);

        vm.prank(pool);
        debtToken.accrueInterest();

        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();
        assertEq(accrued, 0);
        assertEq(retained, 0);
    }

    function testFuzz_accrueInterest_NeverDecreasesIndexOrDebt(
        uint256 borrowRate,
        uint256 retentionRate,
        uint256 amount,
        uint256 elapsed
    ) public {
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        retentionRate = bound(retentionRate, 0, MAX_RETENTION_RATE);
        amount = bound(amount, 1, MAX_AMOUNT);
        elapsed = bound(elapsed, 0, MAX_ACCRUAL_ELAPSED);
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        _setIrmRates(firstIrm, borrowRate, retentionRate);
        uint256 oldIndex = debtToken.getIrmData(address(firstIrm)).storedBorrowIndex;
        uint256 oldScaledDebt = debtToken.getIrmData(address(firstIrm)).totalScaledDebt;
        uint256 oldDebt = debtToken.updatedTotalDebt(address(firstIrm));
        vm.warp(block.timestamp + elapsed);

        vm.prank(pool);
        debtToken.accrueInterest();

        assertGe(debtToken.getIrmData(address(firstIrm)).storedBorrowIndex, oldIndex);
        assertGe(debtToken.updatedTotalDebt(address(firstIrm)), oldDebt);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, oldScaledDebt);
    }

    /// @dev A second accrual in the same block has no elapsed period to charge for, so it must neither move the index
    ///      nor hand over retention a second time.
    function testFuzz_accrueInterest_IsIdempotentWithinSameTimestamp(
        uint256 borrowRate,
        uint256 retentionRate,
        uint256 amount,
        uint256 elapsed
    ) public {
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        retentionRate = bound(retentionRate, 0, MAX_RETENTION_RATE);
        amount = bound(amount, 1, MAX_AMOUNT);
        elapsed = bound(elapsed, 0, MAX_ACCRUAL_ELAPSED);
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), amount);
        _setIrmRates(firstIrm, borrowRate, retentionRate);
        vm.warp(block.timestamp + elapsed);
        vm.prank(pool);
        debtToken.accrueInterest();
        uint256 indexAfterFirst = debtToken.getIrmData(address(firstIrm)).storedBorrowIndex;
        uint256 debtAfterFirst = debtToken.getIrmData(address(firstIrm)).totalScaledDebt;

        vm.prank(pool);
        (uint256 accrued, uint256 retained) = debtToken.accrueInterest();

        assertEq(debtToken.getIrmData(address(firstIrm)).storedBorrowIndex, indexAfterFirst);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, debtAfterFirst);
        assertEq(accrued, 0);
        assertEq(retained, 0);
    }

    // updateBorrowRates()

    function testFuzz_updateBorrowRates_StoresRatesFromIrm(uint256 borrowRate, uint256 retentionRate) public {
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        retentionRate = bound(retentionRate, 0, MAX_RETENTION_RATE);
        _addIrm(firstIrm, 0);
        _mint(bob, MAX_AMOUNT);
        firstIrm.setBorrowRate(borrowRate);
        firstIrm.setRetentionRate(retentionRate);
        debtToken.setLastUpdateTs(block.timestamp);

        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);

        assertEq(debtToken.getIrmData(address(firstIrm)).borrowRate, borrowRate);
        assertEq(debtToken.getIrmData(address(firstIrm)).retentionRate, retentionRate);
    }

    function testFuzz_updateBorrowRates_RevertsWhenBorrowIndexesStale(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, MAX_ELAPSED);
        _addIrm(firstIrm, 0);
        debtToken.setLastUpdateTs(block.timestamp);
        vm.warp(block.timestamp + elapsed);

        vm.expectRevert(MultiInterestDebtToken.BorrowIndexesStale.selector);
        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);
    }

    // _mintDebt()

    function testFuzz_mintDebt_NeverStoresLessDebtThanBorrowed(uint256 amount, uint256 borrowRate, uint256 elapsed)
        public
    {
        amount = bound(amount, 1, MAX_AMOUNT);
        borrowRate = bound(borrowRate, MIN_ACCRUING_BORROW_RATE, MAX_BORROW_RATE);
        elapsed = bound(elapsed, 0, MAX_ACCRUAL_ELAPSED);
        _addIrm(firstIrm, 0);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.warp(block.timestamp + elapsed);

        _mint(bob, amount);

        assertGe(debtToken.balanceOf(bob), amount);
    }

    /// @dev Minting moves the bucket total and the account's scaled balance by the same amount, so a bucket holding two
    ///      borrowers totals exactly their two scaled balances however far its index has moved between the two mints.
    function testFuzz_mintDebt_KeepsBucketTotalEqualToSumOfScaledBalances(
        uint256 firstAmount,
        uint256 secondAmount,
        uint256 borrowRate,
        uint256 elapsed
    ) public {
        firstAmount = bound(firstAmount, 1, MAX_AMOUNT);
        secondAmount = bound(secondAmount, 1, MAX_AMOUNT);
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        elapsed = bound(elapsed, 0, MAX_ACCRUAL_ELAPSED);
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _mint(alice, firstAmount);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.warp(block.timestamp + elapsed);

        _mint(bob, secondAmount);

        assertEq(
            debtToken.getIrmData(address(firstIrm)).totalScaledDebt,
            debtToken.scaledBalanceOf(alice) + debtToken.scaledBalanceOf(bob)
        );
        assertEq(debtToken.getIrmData(address(secondIrm)).totalScaledDebt, 0);
    }

    function testFuzz_mintDebt_RevertsWhenBorrowIndexesStale(uint256 amount, uint256 elapsed) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        elapsed = bound(elapsed, 1, MAX_ELAPSED);
        _addIrm(firstIrm, 0);
        _mint(bob, amount);
        vm.warp(block.timestamp + elapsed);

        vm.expectRevert(MultiInterestDebtToken.BorrowIndexesStale.selector);
        vm.prank(pool);
        debtToken.mint(bob, amount);
    }

    // _burnDebt()

    function testFuzz_burnDebt_ClearsPositionWhenFullBalanceIsRepaid(
        uint256 amount,
        uint256 borrowRate,
        uint256 elapsed
    ) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        elapsed = bound(elapsed, 0, MAX_ACCRUAL_ELAPSED);
        _addIrm(firstIrm, 0);
        _mint(bob, amount);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.warp(block.timestamp + elapsed);

        vm.startPrank(pool);
        debtToken.accrueInterest();
        debtToken.burn(bob, debtToken.balanceOf(bob));
        vm.stopPrank();

        assertEq(debtToken.balanceOf(bob), 0);
        assertEq(debtToken.scaledBalanceOf(bob), 0);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, 0);
    }

    /// @dev Burning moves the bucket total and the account's scaled balance by the same amount, so a partial repayment
    ///      leaves the bucket totalling exactly its two borrowers' scaled balances.
    function testFuzz_burnDebt_KeepsBucketTotalEqualToSumOfScaledBalances(
        uint256 amount,
        uint256 repayment,
        uint256 borrowRate,
        uint256 elapsed
    ) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        elapsed = bound(elapsed, 0, MAX_ACCRUAL_ELAPSED);
        _addIrm(firstIrm, 0);
        _mint(alice, amount);
        _mint(bob, amount);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.warp(block.timestamp + elapsed);
        repayment = bound(repayment, 1, debtToken.balanceOf(bob));

        vm.startPrank(pool);
        debtToken.accrueInterest();
        debtToken.burn(bob, repayment);
        vm.stopPrank();

        assertEq(
            debtToken.getIrmData(address(firstIrm)).totalScaledDebt,
            debtToken.scaledBalanceOf(alice) + debtToken.scaledBalanceOf(bob)
        );
    }

    function testFuzz_burnDebt_UnassignsAccountWhenFullBalanceIsRepaid(
        uint256 amount,
        uint256 borrowRate,
        uint256 elapsed
    ) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        borrowRate = bound(borrowRate, 0, MAX_BORROW_RATE);
        elapsed = bound(elapsed, 0, MAX_ACCRUAL_ELAPSED);
        _addIrm(firstIrm, 0);
        _mint(bob, amount);
        debtToken.setIrmBorrowRate(address(firstIrm), borrowRate);
        vm.warp(block.timestamp + elapsed);

        vm.startPrank(pool);
        debtToken.accrueInterest();
        debtToken.burn(bob, debtToken.balanceOf(bob));
        vm.stopPrank();

        assertEq(debtToken.accountIrmId(bob), address(0));
    }

    function testFuzz_burnDebt_RevertsWhenBorrowIndexesStale(uint256 amount, uint256 elapsed) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        elapsed = bound(elapsed, 1, MAX_ELAPSED);
        _addIrm(firstIrm, 0);
        _mint(bob, amount);
        vm.warp(block.timestamp + elapsed);

        vm.expectRevert(MultiInterestDebtToken.BorrowIndexesStale.selector);
        vm.prank(pool);
        debtToken.burn(bob, amount);
    }

    function _addIrm(MockIrm irm, uint8 priority) internal {
        vm.prank(irmUpdater);
        debtToken.addIrm(address(irm), priority);
    }

    /// @dev Seeds the stored borrow and retention rate for `irm` directly, so index accrual can be exercised without
    ///      routing through the rate subsystem (`updateBorrowRates`).
    function _setIrmRates(MockIrm irm, uint256 borrowRate, uint256 retentionRate) internal {
        debtToken.setIrmBorrowRate(address(irm), borrowRate);
        debtToken.setIrmRetentionRate(address(irm), retentionRate);
    }

    /// @dev Reassigns `account` to `irm`, which `syncAccount` only does if `irm` is the highest-priority applicable active
    ///      IRM. Indexes are refreshed first to satisfy `syncAccount`'s freshness precondition.
    function _syncAccountTo(address account, MockIrm irm) internal {
        firstIrm.setIsApplicable(address(irm) == address(firstIrm));
        secondIrm.setIsApplicable(address(irm) == address(secondIrm));

        vm.startPrank(pool);
        debtToken.accrueInterest();
        debtToken.syncAccount(account);
        vm.stopPrank();

        firstIrm.setIsApplicable(true);
        secondIrm.setIsApplicable(true);
    }

    /// @dev `firstIrm` is the highest-priority IRM and is applicable to every account, so `mint` places the debt in it.
    ///      Indexes are refreshed first to satisfy `mint`'s freshness precondition.
    function _mint(address account, uint256 amount) internal {
        vm.startPrank(pool);
        debtToken.accrueInterest();
        debtToken.mint(account, amount);
        vm.stopPrank();
    }

    function _expectedIrmIdsAfterInsert(uint8 priority) internal view returns (address[] memory irmIds) {
        address[3] memory values = [address(firstIrm), address(secondIrm), address(thirdIrm)];
        irmIds = new address[](4);

        for (uint256 i = 0; i < irmIds.length; i++) {
            if (i < priority) {
                irmIds[i] = values[i];
            } else if (i == priority) {
                irmIds[i] = address(insertedIrm);
            } else {
                irmIds[i] = values[i - 1];
            }
        }
    }

    function _addedIrmIdsWithout(uint8 index) internal view returns (address[] memory irmIds) {
        address[3] memory values = [address(firstIrm), address(secondIrm), address(thirdIrm)];
        irmIds = new address[](2);

        for (uint256 i = 0; i < values.length; i++) {
            if (i < index) {
                irmIds[i] = values[i];
            } else if (i > index) {
                irmIds[i - 1] = values[i];
            }
        }
    }

    function _expectedActiveIrmIdsAfterUndeprecate(uint8 index, uint8 priority)
        internal
        view
        returns (address[] memory irmIds)
    {
        address[3] memory values = [address(firstIrm), address(secondIrm), address(thirdIrm)];
        address[] memory activeIrmIds = _addedIrmIdsWithout(index);
        irmIds = new address[](3);

        for (uint256 i; i < irmIds.length; i++) {
            if (i < priority) {
                irmIds[i] = activeIrmIds[i];
            } else if (i == priority) {
                irmIds[i] = values[index];
            } else {
                irmIds[i] = activeIrmIds[i - 1];
            }
        }
    }

    /// @dev The three IRMs the IRM-management tests add, in the order they are added.
    function _addedIrmIds() internal view returns (address[] memory irmIds) {
        irmIds = new address[](3);
        irmIds[0] = address(firstIrm);
        irmIds[1] = address(secondIrm);
        irmIds[2] = address(thirdIrm);
    }

    function _irmIdAt(uint8 index) internal view returns (address) {
        address[3] memory values = [address(firstIrm), address(secondIrm), address(thirdIrm)];
        return values[index];
    }

    function _singleIrmId(address irmId) internal pure returns (address[] memory irmIds) {
        irmIds = new address[](1);
        irmIds[0] = irmId;
    }

    function _irmPriorityPermutation(uint8 permutation) internal view returns (address[] memory irmIds) {
        irmIds = new address[](3);

        if (permutation == 0) {
            irmIds[0] = address(firstIrm);
            irmIds[1] = address(secondIrm);
            irmIds[2] = address(thirdIrm);
        } else if (permutation == 1) {
            irmIds[0] = address(firstIrm);
            irmIds[1] = address(thirdIrm);
            irmIds[2] = address(secondIrm);
        } else if (permutation == 2) {
            irmIds[0] = address(secondIrm);
            irmIds[1] = address(firstIrm);
            irmIds[2] = address(thirdIrm);
        } else if (permutation == 3) {
            irmIds[0] = address(secondIrm);
            irmIds[1] = address(thirdIrm);
            irmIds[2] = address(firstIrm);
        } else if (permutation == 4) {
            irmIds[0] = address(thirdIrm);
            irmIds[1] = address(firstIrm);
            irmIds[2] = address(secondIrm);
        } else {
            irmIds[0] = address(thirdIrm);
            irmIds[1] = address(secondIrm);
            irmIds[2] = address(firstIrm);
        }
    }
}
