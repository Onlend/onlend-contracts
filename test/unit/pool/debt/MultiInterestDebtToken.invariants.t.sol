// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {MultiInterestDebtToken} from "src/pool/debt/MultiInterestDebtToken.sol";
import {MockIrm} from "../irm/mocks/MockIrm.sol";
import {MultiInterestDebtTokenHarness} from "./mocks/MultiInterestDebtTokenHarness.sol";

/// @notice Stateful handler covering the whole debt lifecycle: interest accrual (`accrueInterest`), rate
///         recomputation (`updateBorrowRates`), IRM reassignment (`syncAccount`), debt creation and repayment (`mint` /
///         `burn`) and the IRM lifecycle (`addIrm`, `deprecateIrm`, `undeprecateIrm`, `removeIrm`, `setIrmPriorities`).
/// @dev    Every action is guarded so the handler never reverts.
///
///         `passTime` is the one action that advances the clock without accruing. Without it every assertion would be
///         taken with `lastUpdateTs == block.timestamp`, where the projecting views collapse onto the stored state and
///         every "projected never below stored" invariant reduces to `x >= x`.
///
///         Expectations recorded for invariants to check against:
///         - `expectedBorrowRate` / `expectedRetentionRate` — the rates last applied through `updateBorrowRates`.
///         - `expectedTotalScaledDebt` / `expectedScaledBalance` — each bucket's scaled total and each account's
///           scaled balance, refreshed only by the actions allowed to move them (`reassign`, `mintDebt`, `burnDebt`),
///           so any movement an accrual action causes is caught.
///         - `previousDebt` / `repaidThisAction` — each borrower's debt as of the start of the current action and what
///           it repaid during it, so debt can be shown to fall only by what was actually repaid.
///         - `retentionFrozen` and `retentionFull` — set by the degenerate rate modes, which pin exact
///           identities no fuzzed rate can.
// forge-lint: disable-next-line(multi-contract-file)
contract MultiInterestDebtTokenHandler is Test {
    MultiInterestDebtTokenHarness public debtToken;
    address public pool;
    address public irmUpdater;
    MockIrm[] public irms;
    /// @notice IRMs removed through `removeIrm` and not yet added back through `reAddIrm`.
    address[] public removedIrmIds;
    address[] public borrowers;
    /// @notice Leading borrowers held on their originally-assigned IRM, excluded from reassignment and repayment and
    ///         given no applicable IRM when minted debt, so those buckets stay funded for the whole run.
    uint256 public pinnedBorrowers;

    mapping(address irm => uint256) public expectedBorrowRate;
    mapping(address irm => uint256) public expectedRetentionRate;
    mapping(address irm => uint256) public expectedTotalScaledDebt;
    mapping(address borrower => uint256) public expectedScaledBalance;
    mapping(address borrower => uint256) public previousDebt;
    mapping(address borrower => uint256) public repaidThisAction;
    bool public retentionFrozen;
    bool public retentionFull;

    uint256 constant IDLE_LIQUIDITY = 5000e18;
    uint256 constant MAX_BORROW_RATE = 10e18; // 1000% APR
    uint256 constant MAX_RETENTION_RATE = 1e18; // 100%
    uint256 constant MAX_ELAPSED = 30 days;
    uint256 constant MAX_MINT = 1_000_000e18;

    /// @dev Rate modes. `NORMAL` fuzzes both rates; the other two pin one of them to a boundary where an exact
    ///      identity holds — no retention accrues nothing, full retention leaves depositors nothing.
    uint256 constant NORMAL_MODE = 0;
    uint256 constant ZERO_RETENTION_MODE = 1;
    uint256 constant FULL_RETENTION_MODE = 2;

    constructor(
        MultiInterestDebtTokenHarness _debtToken,
        address _pool,
        address _irmUpdater,
        MockIrm[] memory _irms,
        address[] memory _borrowers,
        uint256 _pinnedBorrowers
    ) {
        debtToken = _debtToken;
        pool = _pool;
        irmUpdater = _irmUpdater;
        for (uint256 i; i < _irms.length; i++) {
            irms.push(_irms[i]);
        }
        for (uint256 i; i < _borrowers.length; i++) {
            borrowers.push(_borrowers[i]);
        }
        pinnedBorrowers = _pinnedBorrowers;

        _refreshExpectedScaledDebt();
    }

    /// @dev Advances time without accruing, leaving the stored indexes behind the current block so the projecting
    ///      views (`updatedBorrowIndex`, `updatedTotalDebt`, `balanceOf`, `totalSupply`, `totalRetained`) are asserted
    ///      on against a genuinely stale stored state.
    function passTime(uint256 elapsed) external {
        _startAction();
        vm.warp(block.timestamp + bound(elapsed, 1, MAX_ELAPSED));
    }

    /// @dev Adds a fresh IRM at a fuzzed priority, exercising the ordered insert that shifts the incumbents right.
    function addIrm(uint256 prioritySeed) external {
        _startAction();
        if (debtToken.getSupportedIrmIds().length >= debtToken.MAX_SUPPORTED_IRMS()) return;
        uint256 activeCount = debtToken.getActiveIrmIds().length;
        if (activeCount >= debtToken.MAX_ACTIVE_IRMS()) return;

        MockIrm irm = new MockIrm(true, 0, 0);
        irms.push(irm);

        vm.prank(irmUpdater);
        debtToken.addIrm(address(irm), uint8(bound(prioritySeed, 0, activeCount)));
    }

    /// @dev Adds back an IRM removed earlier at a fuzzed priority. It starts from fresh accounting data, so its expected
    ///      rates are cleared to match.
    function reAddIrm(uint256 irmSeed, uint256 prioritySeed) external {
        _startAction();
        if (debtToken.getSupportedIrmIds().length >= debtToken.MAX_SUPPORTED_IRMS()) return;
        uint256 activeCount = debtToken.getActiveIrmIds().length;
        if (activeCount >= debtToken.MAX_ACTIVE_IRMS()) return;
        if (removedIrmIds.length == 0) return;

        uint256 index = bound(irmSeed, 0, removedIrmIds.length - 1);
        address irmId = removedIrmIds[index];
        removedIrmIds[index] = removedIrmIds[removedIrmIds.length - 1];
        removedIrmIds.pop();

        vm.prank(irmUpdater);
        debtToken.addIrm(irmId, uint8(bound(prioritySeed, 0, activeCount)));

        expectedBorrowRate[irmId] = 0;
        expectedRetentionRate[irmId] = 0;
    }

    /// @dev Deprecates an active IRM, exercising the ordered removal.
    function deprecateIrm(uint256 irmSeed) external {
        _startAction();
        address[] memory activeIrmIds = debtToken.getActiveIrmIds();
        if (activeIrmIds.length == 0) return;

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(activeIrmIds[bound(irmSeed, 0, activeIrmIds.length - 1)]);
    }

    /// @dev Returns a deprecated IRM to the active list at a fuzzed priority.
    function undeprecateIrm(uint256 irmSeed, uint256 prioritySeed) external {
        _startAction();
        address[] memory deprecatedIrmIds = debtToken.getDeprecatedIrmIds();
        uint256 activeCount = debtToken.getActiveIrmIds().length;
        if (deprecatedIrmIds.length == 0 || activeCount >= debtToken.MAX_ACTIVE_IRMS()) return;

        vm.prank(irmUpdater);
        debtToken.undeprecateIrm(
            deprecatedIrmIds[bound(irmSeed, 0, deprecatedIrmIds.length - 1)], uint8(bound(prioritySeed, 0, activeCount))
        );
    }

    /// @dev Removes a supported IRM holding no debt, whether active or deprecated.
    function removeIrm(uint256 irmSeed) external {
        _startAction();
        address[] memory supportedIrmIds = debtToken.getSupportedIrmIds();
        address[] memory removableIrmIds = new address[](supportedIrmIds.length);
        uint256 removableCount;
        for (uint256 i; i < supportedIrmIds.length; i++) {
            if (debtToken.getIrmData(supportedIrmIds[i]).totalScaledDebt == 0) {
                removableIrmIds[removableCount++] = supportedIrmIds[i];
            }
        }
        if (removableCount == 0) return;
        address irmId = removableIrmIds[bound(irmSeed, 0, removableCount - 1)];

        vm.prank(irmUpdater);
        debtToken.removeIrm(irmId);

        removedIrmIds.push(irmId);
    }

    /// @dev Reorders the active IRMs by rotating the list, which is a permutation for any offset and so always
    ///      satisfies the "each active IRM exactly once" requirement.
    function rotateIrmPriorities(uint256 offsetSeed) external {
        _startAction();
        address[] memory activeIrmIds = debtToken.getActiveIrmIds();
        if (activeIrmIds.length == 0) return;

        uint256 offset = bound(offsetSeed, 0, activeIrmIds.length - 1);
        address[] memory rotatedIrmIds = new address[](activeIrmIds.length);
        for (uint256 i; i < activeIrmIds.length; i++) {
            rotatedIrmIds[i] = activeIrmIds[(i + offset) % activeIrmIds.length];
        }

        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(rotatedIrmIds);
    }

    /// @dev Advances time and accrues borrow indexes using the currently stored per-IRM rates. `elapsed` starts at
    ///      zero so a second update within the same block is exercised, which must leave the indexes untouched.
    function advanceIndexes(uint256 elapsed) external {
        _startAction();
        vm.warp(block.timestamp + bound(elapsed, 0, MAX_ELAPSED));

        _accrue();
    }

    /// @dev Advances time, accrues indexes with the old rates, then applies fresh rates through `updateBorrowRates`.
    ///      Indexes are refreshed in the same block first so the freshness precondition holds.
    ///
    ///      Each IRM gets its own rate derived from the fuzzed seed rather than a shared one. Equal rates would keep
    ///      every borrow index identical, making a reassignment restate debt between two equal indexes — a no-op that
    ///      hides whether the restatement is done correctly at all.
    function refreshRates(uint256 elapsed, uint256 borrowRateSeed, uint256 retentionRateSeed, uint256 modeSeed)
        external
    {
        _startAction();
        vm.warp(block.timestamp + bound(elapsed, 1, MAX_ELAPSED));
        _accrue();

        uint256 mode = bound(modeSeed, NORMAL_MODE, FULL_RETENTION_MODE);
        for (uint256 i; i < irms.length; i++) {
            uint256 irmBorrowRate = bound(uint256(keccak256(abi.encode(borrowRateSeed, i))), 0, MAX_BORROW_RATE);
            uint256 irmRetentionRate = _retentionRateFor(mode, retentionRateSeed, i);
            irms[i].setBorrowRate(irmBorrowRate);
            irms[i].setRetentionRate(irmRetentionRate);
            expectedBorrowRate[address(irms[i])] = irmBorrowRate;
            expectedRetentionRate[address(irms[i])] = irmRetentionRate;
        }

        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);

        retentionFull = mode == FULL_RETENTION_MODE;
        retentionFrozen = mode == ZERO_RETENTION_MODE;
    }

    /// @dev Syncs a borrower against a fuzzed set of applicable IRMs, restating its debt against the borrow index of
    ///      the one it moves to. Indexes are refreshed in the same block first so the freshness precondition holds.
    function reassign(uint256 borrowerSeed, uint256 applicableMask) external {
        _startAction();
        _accrue();

        address borrower = borrowers[bound(borrowerSeed, pinnedBorrowers, borrowers.length - 1)];
        _setApplicableIrms(applicableMask);

        vm.prank(pool);
        debtToken.syncAccount(borrower);

        _refreshExpectedScaledDebt();
    }

    /// @dev Creates debt for a borrower against a fuzzed set of applicable IRMs, which `mint` assigns from if the
    ///      borrower holds no debt and syncs against afterwards. Pinned borrowers get none, holding them on their
    ///      deprecated IRMs. Indexes are refreshed in the same block first so the freshness precondition holds. Skipped
    ///      for a borrower holding no debt when no active IRM applies, leaving none to assign it.
    function mintDebt(uint256 borrowerSeed, uint256 applicableMask, uint256 amount) external {
        _startAction();
        _accrue();

        uint256 borrowerIndex = bound(borrowerSeed, 0, borrowers.length - 1);
        address borrower = borrowers[borrowerIndex];
        _setApplicableIrms(borrowerIndex < pinnedBorrowers ? 0 : applicableMask);
        if (debtToken.scaledBalanceOf(borrower) == 0 && !_anyActiveIrmApplicable()) return;

        vm.prank(pool);
        debtToken.mint(borrower, bound(amount, 1, MAX_MINT));

        _refreshExpectedScaledDebt();
    }

    /// @dev Repays part or all of a borrower's debt, which `burn` syncs against a fuzzed set of applicable IRMs if any
    ///      debt remains. The repayment is capped at the borrower's own debt, so the scaled amount it clears can never
    ///      exceed either the borrower's scaled balance or its bucket's scaled total — an underflow here means the two
    ///      have drifted apart, which is exactly what the suite is looking for.
    function burnDebt(uint256 borrowerSeed, uint256 applicableMask, uint256 amount) external {
        _startAction();
        _accrue();

        address borrower = borrowers[bound(borrowerSeed, pinnedBorrowers, borrowers.length - 1)];
        uint256 debt = debtToken.balanceOf(borrower);
        if (debt == 0) return;
        uint256 repayment = bound(amount, 1, debt);
        _setApplicableIrms(applicableMask);

        vm.prank(pool);
        debtToken.burn(borrower, repayment);

        repaidThisAction[borrower] = repayment;
        _refreshExpectedScaledDebt();
    }

    /// @dev Records every borrower's debt as of the start of an action, before any time warp or state change, and
    ///      clears the repayments carried over from the previous action.
    function _startAction() private {
        for (uint256 i; i < borrowers.length; i++) {
            previousDebt[borrowers[i]] = debtToken.balanceOf(borrowers[i]);
            repaidThisAction[borrowers[i]] = 0;
        }
    }

    function _accrue() private {
        vm.prank(pool);
        debtToken.accrueInterest();
    }

    /// @dev Re-reads every bucket's scaled total and every account's scaled balance after an action allowed to move
    ///      them. Both sides are recorded because a rebasing accrual would move them together, leaving the bucket
    ///      total still equal to the sum of its balances and so passing every cross-check on the two.
    function _refreshExpectedScaledDebt() private {
        address[] memory supportedIrmIds = debtToken.getSupportedIrmIds();
        for (uint256 i; i < supportedIrmIds.length; i++) {
            expectedTotalScaledDebt[supportedIrmIds[i]] = debtToken.getIrmData(supportedIrmIds[i]).totalScaledDebt;
        }
        for (uint256 i; i < borrowers.length; i++) {
            expectedScaledBalance[borrowers[i]] = debtToken.scaledBalanceOf(borrowers[i]);
        }
    }

    /// @dev Sets each IRM's applicability from one bit of `applicableMask`, so a sync may face several applicable IRMs
    ///      and have to pick the highest-priority one, or none and have to keep the account where it is. Every action
    ///      that syncs sets this first, so it never needs resetting.
    function _setApplicableIrms(uint256 applicableMask) private {
        for (uint256 i; i < irms.length; i++) {
            irms[i].setIsApplicable((applicableMask >> i) & 1 == 1);
        }
    }

    /// @dev Whether any active IRM currently applies, i.e. whether `mint` can assign an account holding no debt.
    function _anyActiveIrmApplicable() private view returns (bool) {
        address[] memory activeIrmIds = debtToken.getActiveIrmIds();
        for (uint256 i; i < activeIrmIds.length; i++) {
            if (MockIrm(activeIrmIds[i]).isApplicable(address(0))) return true;
        }
        return false;
    }

    function _retentionRateFor(uint256 mode, uint256 retentionRateSeed, uint256 index) private pure returns (uint256) {
        if (mode == ZERO_RETENTION_MODE) return 0;
        if (mode == FULL_RETENTION_MODE) return MAX_RETENTION_RATE;
        return bound(uint256(keccak256(abi.encode(retentionRateSeed, index))), 0, MAX_RETENTION_RATE);
    }
}

// forge-lint: disable-next-line(multi-contract-file)
contract MultiInterestDebtTokenInvariantsTest is Test {
    MultiInterestDebtTokenHarness internal debtToken;
    MultiInterestDebtTokenHandler internal handler;
    MockIrm[] internal irms;
    address[] internal borrowers;

    address internal pool = makeAddr("pool");
    address internal defaultAdmin = makeAddr("defaultAdmin");
    address internal irmUpdater = makeAddr("irmUpdater");

    string constant NAME = "dOnlend USD Coin";
    string constant SYMBOL = "dOnlend USDC";
    uint8 constant DECIMALS = 6;

    uint256 constant SEED_DEBT = 1000e18;
    /// @dev Borrowers 0 and 1 are assigned to the two IRMs deprecated below and are pinned there, so both the active
    ///      and the deprecated list keep carrying debt for the whole run rather than draining on the first
    ///      reassignment or repayment.
    uint256 constant PINNED_BORROWERS = 2;

    function setUp() public {
        MultiInterestDebtTokenHarness implementation = new MultiInterestDebtTokenHarness();
        debtToken = MultiInterestDebtTokenHarness(Clones.clone(address(implementation)));
        debtToken.initialize(pool, NAME, SYMBOL, DECIMALS, defaultAdmin, irmUpdater, new address[](0));

        // Seed four IRMs, each funded with debt, then deprecate two so both the active and deprecated lists — which
        // the two update functions both iterate — carry outstanding debt.
        // Each IRM is inserted at priority 0, making it the highest-priority applicable IRM at the moment its borrower's
        // debt is minted, so borrower `i` is assigned to `irms[i]`.
        for (uint256 i; i < 4; i++) {
            MockIrm irm = new MockIrm(true, 0, 0);
            irms.push(irm);
            vm.prank(irmUpdater);
            debtToken.addIrm(address(irm), 0);

            address borrower = makeAddr(string.concat("borrower", vm.toString(i)));
            borrowers.push(borrower);
            vm.startPrank(pool);
            debtToken.accrueInterest();
            debtToken.mint(borrower, SEED_DEBT * (i + 1));
            vm.stopPrank();
        }
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(irms[0]));
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(irms[1]));

        handler = new MultiInterestDebtTokenHandler(debtToken, pool, irmUpdater, irms, borrowers, PINNED_BORROWERS);

        targetContract(address(handler));
    }

    /// @dev Borrow indexes are only ever accrued up to the current block, never into the future.
    function invariant_LastUpdateTsNotInFuture() public view {
        assertLe(debtToken.lastUpdateTs(), block.timestamp);
    }

    /// @dev The active list is maintained by ordered insertion and removal alongside a status flag and a separate
    ///      supported list, so the three can desync without anything reverting. `getDeprecatedIrmIds` sizes its return
    ///      from the difference of the two list lengths, and would hand back zero-address holes if that ever stopped
    ///      matching the statuses it filters on.
    function invariant_IrmListsAreConsistent() public view {
        address[] memory activeIrmIds = debtToken.getActiveIrmIds();
        address[] memory deprecatedIrmIds = debtToken.getDeprecatedIrmIds();
        address[] memory supportedIrmIds = debtToken.getSupportedIrmIds();

        assertEq(activeIrmIds.length + deprecatedIrmIds.length, supportedIrmIds.length);
        assertLe(activeIrmIds.length, debtToken.MAX_ACTIVE_IRMS());
        assertLe(supportedIrmIds.length, debtToken.MAX_SUPPORTED_IRMS());

        for (uint256 i; i < activeIrmIds.length; i++) {
            assertTrue(debtToken.getIrmData(activeIrmIds[i]).status == MultiInterestDebtToken.IrmStatus.ACTIVE);
            for (uint256 j = i + 1; j < activeIrmIds.length; j++) {
                assertNotEq(activeIrmIds[i], activeIrmIds[j]);
            }
        }
        for (uint256 i; i < deprecatedIrmIds.length; i++) {
            assertNotEq(deprecatedIrmIds[i], address(0));
        }
    }

    /// @dev Mint assigns an account an IRM before creating its debt and burn clears the assignment once the debt is
    ///      gone, so an account is assigned exactly while it holds scaled debt. `removeIrm` only removes an IRM holding
    ///      no debt, so that IRM is always supported (active or deprecated); otherwise `balanceOf` would report zero and
    ///      the position would be stranded outside every accrual loop.
    function invariant_AccountIsAssignedToSupportedIrmExactlyWhileHoldingDebt() public view {
        for (uint256 i; i < borrowers.length; i++) {
            address irmId = debtToken.accountIrmId(borrowers[i]);
            if (debtToken.scaledBalanceOf(borrowers[i]) == 0) {
                assertEq(irmId, address(0));
            } else {
                assertTrue(debtToken.isIrmSupported(irmId));
            }
        }
    }

    /// @dev A borrow index starts at `ONE_18_DP` and only ever compounds upward, so the stored index is never below
    ///      one and the index projected to the current block is never below the stored index.
    function invariant_BorrowIndexNeverBelowOne() public view {
        address[] memory supportedIrmIds = debtToken.getSupportedIrmIds();

        for (uint256 i; i < supportedIrmIds.length; i++) {
            address irmId = supportedIrmIds[i];
            uint256 storedIndex = debtToken.getIrmData(irmId).storedBorrowIndex;
            assertGe(storedIndex, MathUtils.ONE_18_DP);
            assertGe(debtToken.updatedBorrowIndex(irmId), storedIndex);
        }
    }

    /// @dev The debt projected to the current block is never below the debt the stored index states — accrual only
    ///      adds interest, it never claws back.
    function invariant_UpdatedTotalDebtNeverBelowStored() public view {
        address[] memory supportedIrmIds = debtToken.getSupportedIrmIds();

        for (uint256 i; i < supportedIrmIds.length; i++) {
            address irmId = supportedIrmIds[i];
            MultiInterestDebtToken.IrmData memory irmData = debtToken.getIrmData(irmId);
            uint256 storedDebt = Math.mulDiv(
                irmData.totalScaledDebt, irmData.storedBorrowIndex, MathUtils.ONE_18_DP, Math.Rounding.Ceil
            );
            assertGe(debtToken.updatedTotalDebt(irmId), storedDebt);
        }
    }

    /// @dev The property scaled accounting exists to guarantee: a bucket's scaled total is the exact sum of its
    ///      accounts' scaled balances, so nothing can make the two drift apart and leave a repayment underflowing.
    ///      Reassignment, minting and repayment all put this at risk — each debits or credits a bucket and an account
    ///      by an amount it converts through a borrow index, and the two sides must move by the same integer.
    function invariant_TotalScaledDebtEqualsSumOfScaledBalances() public view {
        address[] memory supportedIrmIds = debtToken.getSupportedIrmIds();

        for (uint256 i; i < supportedIrmIds.length; i++) {
            address irmId = supportedIrmIds[i];
            uint256 sumScaledBalances;
            for (uint256 j; j < borrowers.length; j++) {
                if (debtToken.accountIrmId(borrowers[j]) == irmId) {
                    sumScaledBalances += debtToken.scaledBalanceOf(borrowers[j]);
                }
            }
            assertEq(debtToken.getIrmData(irmId).totalScaledDebt, sumScaledBalances);
        }
    }

    /// @dev Scaled debt is index-normalised, so interest accrues through the borrow index alone and no stored scaled
    ///      amount is rewritten as it accrues — only mint, burn and IRM reassignment move one. Those three actions are
    ///      the only ones that refresh the expectations, so any movement an accrual or IRM-lifecycle action causes
    ///      fails here. Both the bucket totals and the account balances are pinned: an accrual that rebased both
    ///      together would keep each bucket equal to the sum of its balances and so slip past
    ///      `invariant_TotalScaledDebtEqualsSumOfScaledBalances`.
    function invariant_ScaledDebtIsUnchangedByAccrual() public view {
        address[] memory supportedIrmIds = debtToken.getSupportedIrmIds();

        for (uint256 i; i < supportedIrmIds.length; i++) {
            address irmId = supportedIrmIds[i];
            assertEq(debtToken.getIrmData(irmId).totalScaledDebt, handler.expectedTotalScaledDebt(irmId));
        }
        for (uint256 i; i < borrowers.length; i++) {
            assertEq(debtToken.scaledBalanceOf(borrowers[i]), handler.expectedScaledBalance(borrowers[i]));
        }
    }

    /// @dev Total supply states each bucket's debt from its scaled total in one conversion, while `balanceOf` converts
    ///      each account separately; both round up, so the per-account sum is the larger of the two by at most one
    ///      unit of rounding dust per account. A gap wider than that means an account's debt is no longer accounted
    ///      for in the bucket it sits in.
    function invariant_TotalSupplyNeverExceedsSumOfBorrowerDebts() public view {
        uint256 sumDebts;
        for (uint256 i; i < borrowers.length; i++) {
            sumDebts += debtToken.balanceOf(borrowers[i]);
        }
        uint256 totalDebt = debtToken.totalSupply();

        assertLe(totalDebt, sumDebts);
        assertLe(sumDebts - totalDebt, borrowers.length);
    }

    /// @dev Interest only ever adds to a position and a reassignment restates it through two conversions that both
    ///      round up, so repayment is the only thing that can reduce what a borrower owes — and never by more than
    ///      what it repaid. A reassignment that rounded the other way would discharge debt on every IRM move, and a
    ///      repayment that cleared more scaled debt than it paid for would discharge it on every repayment.
    function invariant_BorrowerDebtNeverDecreasesBeyondRepayment() public view {
        for (uint256 i; i < borrowers.length; i++) {
            address borrower = borrowers[i];
            assertGe(debtToken.balanceOf(borrower) + handler.repaidThisAction(borrower), handler.previousDebt(borrower));
        }
    }

    /// @dev A zero retention rate retains none of the interest it accrues. With every IRM at zero, nothing projects,
    ///      whatever the borrow rates or the debt outstanding.
    function invariant_NothingIsRetainedWhileRetentionRatesAreZero() public view {
        if (!handler.retentionFrozen()) return;

        (, uint256 retained) = debtToken.pendingInterest();
        assertEq(retained, 0);
    }

    /// @dev Interest is handed to the pool and not kept, so once an action has accrued there is nothing left pending
    ///      until the clock moves on. `passTime` is the only action that leaves a pending amount behind.
    function invariant_PendingInterestIsZeroWhileIndexesAreFresh() public view {
        // Exact equality checks same-block freshness, regardless of the timestamp chosen.
        // forge-lint: disable-next-line(block-timestamp)
        if (debtToken.lastUpdateTs() != block.timestamp) return;

        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();
        assertEq(accrued, 0);
        assertEq(retained, 0);
    }

    /// @dev A full retention rate retains all the interest and leaves depositors nothing, whatever the borrow rate or
    ///      the outstanding debt. Read live rather than snapshotted at the last rate update, so the debt it prices has
    ///      accrued since.
    function invariant_AllInterestIsRetainedWhileRetentionRatesAreFull() public view {
        if (!handler.retentionFull()) return;

        (uint256 interest, uint256 retained) = debtToken.annualInterest();
        assertEq(retained, interest);
    }

    /// @dev `updateBorrowRates` writes each IRM's rates straight from its IIRM; nothing else mutates the stored
    ///      rates, so they always equal the rates last applied through the rate subsystem. Deprecated IRMs are
    ///      included, since they keep accruing and so keep needing rates.
    function invariant_StoredRatesMatchLastApplied() public view {
        address[] memory supportedIrmIds = debtToken.getSupportedIrmIds();

        for (uint256 i; i < supportedIrmIds.length; i++) {
            address irmId = supportedIrmIds[i];
            assertEq(debtToken.getIrmData(irmId).borrowRate, handler.expectedBorrowRate(irmId));
            assertEq(debtToken.getIrmData(irmId).retentionRate, handler.expectedRetentionRate(irmId));
        }
    }
}
