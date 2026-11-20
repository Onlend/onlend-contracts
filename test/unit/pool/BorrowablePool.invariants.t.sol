// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {BorrowablePool} from "src/pool/BorrowablePool.sol";
import {FeeConstants} from "src/pool/lib/FeeConstants.sol";
import {ShareMath} from "src/pool/lib/ShareMath.sol";
import {MockDebtToken} from "./mocks/MockDebtToken.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFlashBorrower} from "./mocks/MockFlashBorrower.sol";
import {MockOnlendFeeRegistry} from "./mocks/MockOnlendFeeRegistry.sol";

/// @notice Drives valid BorrowablePool operations across a fixed set of actors.
/// @dev Every action is bounded or guarded so the handler does not produce expected reverts.
///
///      Each action asserts only the pool's own accounting across the state the sequence has built up: that underlying,
///      debt and total assets move together, and that booking fees moves no value. Which account a call credits or
///      debits is the operation's own output, pinned against fixed amounts by the unit tests, so it is not restated
///      here; where shares and collateral end up is covered by the supply and backing invariants instead.
// forge-lint: disable-next-line(multi-contract-file)
contract BorrowablePoolHandler is Test {
    struct AccountingSnapshot {
        /// @dev The underlying the pool holds, which a donation can raise above what the pool has accounted for.
        uint256 balance;
        uint256 debt;
        uint256 totalAssets;
    }

    uint256 internal constant MAX_ACTION_AMOUNT = 1e30;

    BorrowablePool internal pool;
    MockERC20 internal asset;
    MockDebtToken internal debtToken;
    MockOnlendFeeRegistry internal feeRegistry;
    address internal lendingCore;
    address[] internal actors;
    /// @dev Whether a flash loan may run a write-off, which must be disabled if write-offs are excluded.
    bool internal writeOffEnabled;

    uint256 public donatedAssets;
    uint256 public donatedShares;

    /// @dev The pool's accounting just before the flash loan in flight went out, and the amount it lent.
    AccountingSnapshot private _beforeLoan;
    uint256 private _loanAmount;

    modifier trackSharePrice() {
        uint256 previousTotalAssets = pool.totalAssets();
        uint256 previousTotalSupply = pool.totalSupply();
        _;
        _assertSharePriceNotDecreased(previousTotalAssets, previousTotalSupply);
    }

    constructor(
        BorrowablePool pool_,
        MockERC20 asset_,
        MockDebtToken debtToken_,
        MockOnlendFeeRegistry feeRegistry_,
        address lendingCore_,
        address[] memory actors_,
        bool writeOffEnabled_
    ) {
        pool = pool_;
        asset = asset_;
        debtToken = debtToken_;
        feeRegistry = feeRegistry_;
        lendingCore = lendingCore_;
        actors = actors_;
        writeOffEnabled = writeOffEnabled_;
    }

    function deposit(uint256 callerSeed, uint256 receiverSeed, uint256 rawAssets) external trackSharePrice {
        uint256 maxAssets = Math.min(pool.maxDeposit(_actor(receiverSeed)), MAX_ACTION_AMOUNT);
        uint256 minAssets = pool.previewMint(1);
        if (maxAssets < minAssets) return;

        address caller = _actor(callerSeed);
        uint256 assets = bound(rawAssets, minAssets, maxAssets);
        _mintAndApprove(caller, assets);
        AccountingSnapshot memory before_ = _accountingSnapshot();

        vm.prank(caller);
        pool.deposit(assets, _actor(receiverSeed));

        _assertAssetFlow(before_, assets, 0);
    }

    function mint(uint256 callerSeed, uint256 receiverSeed, uint256 rawShares) external trackSharePrice {
        uint256 maxShares = Math.min(pool.maxMint(_actor(receiverSeed)), MAX_ACTION_AMOUNT);
        if (maxShares == 0) return;

        uint256 shares = bound(rawShares, 1, maxShares);
        uint256 assets = pool.previewMint(shares);
        if (assets > MAX_ACTION_AMOUNT) return;

        address caller = _actor(callerSeed);
        _mintAndApprove(caller, assets);
        AccountingSnapshot memory before_ = _accountingSnapshot();

        vm.prank(caller);
        pool.mint(shares, _actor(receiverSeed));

        _assertAssetFlow(before_, assets, 0);
    }

    function withdraw(uint256 ownerSeed, uint256 receiverSeed, uint256 rawAssets) external trackSharePrice {
        address owner = _actor(ownerSeed);
        uint256 maxAssets = Math.min(pool.maxWithdraw(owner), MAX_ACTION_AMOUNT);
        if (maxAssets == 0) return;

        uint256 assets = bound(rawAssets, 1, maxAssets);
        AccountingSnapshot memory before_ = _accountingSnapshot();

        vm.prank(owner);
        pool.withdraw(assets, _actor(receiverSeed), owner);

        _assertAssetFlow(before_, 0, assets);
    }

    function redeem(uint256 ownerSeed, uint256 receiverSeed, uint256 rawShares) external trackSharePrice {
        address owner = _actor(ownerSeed);
        uint256 maxShares = Math.min(pool.maxRedeem(owner), MAX_ACTION_AMOUNT);
        /// @dev Below a share price of one, a single share can price to no assets, which `redeem` rejects.
        uint256 minShares = pool.previewWithdraw(1);
        if (maxShares < minShares) return;

        uint256 shares = bound(rawShares, minShares, maxShares);
        uint256 assets = pool.previewRedeem(shares);
        AccountingSnapshot memory before_ = _accountingSnapshot();

        vm.prank(owner);
        pool.redeem(shares, _actor(receiverSeed), owner);

        _assertAssetFlow(before_, 0, assets);
    }

    /// @dev Redistributes shares so the supply and per-account invariants are checked against many different splits,
    ///      self-transfers included. Where the shares land is asserted by those invariants, not here.
    function transfer(uint256 senderSeed, uint256 receiverSeed, uint256 rawShares) external trackSharePrice {
        address sender = _actor(senderSeed);
        uint256 maxShares = Math.min(pool.balanceOf(sender), MAX_ACTION_AMOUNT);
        if (maxShares == 0) return;

        uint256 shares = bound(rawShares, 1, maxShares);

        vm.prank(sender);
        assertTrue(pool.transfer(_actor(receiverSeed), shares));
    }

    function donateAssets(uint256 donorSeed, uint256 rawAssets) external trackSharePrice {
        address donor = _actor(donorSeed);
        uint256 assets = bound(rawAssets, 1, MAX_ACTION_AMOUNT);
        asset.mint(donor, assets);

        vm.prank(donor);
        assertTrue(asset.transfer(address(pool), assets));

        donatedAssets += assets;
    }

    function donateShares(uint256 donorSeed, uint256 rawShares) external trackSharePrice {
        address donor = _actor(donorSeed);
        uint256 maxShares = Math.min(pool.balanceOf(donor), MAX_ACTION_AMOUNT);
        if (maxShares == 0) return;

        uint256 shares = bound(rawShares, 1, maxShares);

        vm.prank(donor);
        assertTrue(pool.transfer(address(pool), shares));

        donatedShares += shares;
    }

    function syncInterestRate(uint256 borrowerSeed, uint256 rawInterest, uint256 rawRetained) external trackSharePrice {
        if (!_seedInterest(borrowerSeed, rawInterest, rawRetained)) return;

        uint256 assetsWhilePending = pool.totalAssets();
        uint256 supplyWhilePending = pool.totalSupply();
        uint256 operatorFeeSharesWhilePending = pool.totalOperatorFeeShares();
        uint256 onlendFeeSharesWhilePending = pool.totalOnlendFeeShares();
        pool.syncInterestRate();

        /// @dev Fees priced while pending must buy the same shares once booked, so booking hands the operator and Onlend
        ///      their shares while moving no assets and no supply. All the readings are trivially equal while nothing is
        ///      pending, which the zero end of `retained` under a zero fee configuration covers.
        (uint256 pendingAccrued, uint256 pendingRetained) = debtToken.pendingInterest();
        assertEq(pool.totalAssets(), assetsWhilePending, "assets moved on booking fees");
        assertEq(pool.totalSupply(), supplyWhilePending, "supply moved on booking fees");
        assertEq(pool.totalOperatorFeeShares(), operatorFeeSharesWhilePending, "operator fee total moved on booking");
        assertEq(pool.totalOnlendFeeShares(), onlendFeeSharesWhilePending, "Onlend fee total moved on booking");
        assertEq(pendingAccrued, 0, "interest was left pending");
        assertEq(pendingRetained, 0, "retention was left pending");
    }

    /// @dev Leaves interest accrued by the debt token but unbooked by the pool, so later actions price against a
    ///      pending amount. Asserts nothing: it exists to reach that state, and `syncInterestRate` owns the identity
    ///      that booking it changes nothing.
    function seedPendingInterest(uint256 borrowerSeed, uint256 rawInterest, uint256 rawRetained)
        external
        trackSharePrice
    {
        _seedInterest(borrowerSeed, rawInterest, rawRetained);
    }

    /// @dev Changes the registry's fee configuration, which the pool only picks up on its next rate update, so later
    ///      actions accrue under a configuration the pool has not yet read.
    function setFeeConfig(uint16 rawFixedFeeBps, uint16 rawSplitFeeBps) external trackSharePrice {
        feeRegistry.setFeeConfig(
            uint16(bound(rawFixedFeeBps, 0, FeeConstants.MAX_FEE_BPS)),
            uint16(bound(rawSplitFeeBps, 0, FeeConstants.MAX_FEE_BPS))
        );
    }

    function claimFeeShares(uint256 callerSeed) external trackSharePrice {
        if (pool.totalOperatorFeeShares() == 0 && pool.totalOnlendFeeShares() == 0) return;

        uint256 totalSupplyBefore = pool.totalSupply();

        vm.prank(_actor(callerSeed));
        pool.claimFeeShares();

        assertEq(pool.totalSupply(), totalSupplyBefore);
    }

    function borrow(uint256 borrowerSeed, uint256 receiverSeed, uint256 rawAmount) external trackSharePrice {
        uint256 maxAmount = Math.min(pool.idleLiquidity(), MAX_ACTION_AMOUNT);
        if (maxAmount == 0) return;

        uint256 amount = bound(rawAmount, 1, maxAmount);
        AccountingSnapshot memory before_ = _accountingSnapshot();

        vm.prank(lendingCore);
        pool.borrow(_actor(borrowerSeed), amount, _actor(receiverSeed));

        assertEq(asset.balanceOf(address(pool)), before_.balance - amount);
        assertEq(debtToken.totalSupply(), before_.debt + amount);
        assertEq(pool.totalAssets(), before_.totalAssets);
    }

    /// @dev Split from `repayFull` so each side pins an exact repayment against an independently bounded amount,
    ///      rather than restating the cap the implementation applies.
    function repayPartial(uint256 payerSeed, uint256 borrowerSeed, uint256 rawAmount) external trackSharePrice {
        address borrower = _actor(borrowerSeed);
        uint256 debt = debtToken.balanceOf(borrower);
        if (debt < 2) return;

        address payer = _actor(payerSeed);
        uint256 amount = bound(rawAmount, 1, debt - 1);
        _mintAndApprove(payer, amount);
        AccountingSnapshot memory before_ = _accountingSnapshot();

        vm.prank(lendingCore);
        uint256 repayment = pool.repay(payer, amount, borrower);

        assertEq(repayment, amount, "an amount below the debt was not repaid in full");
        _assertRepaymentFlow(before_, repayment);
    }

    function repayFull(uint256 payerSeed, uint256 borrowerSeed, uint256 rawAmount) external trackSharePrice {
        address borrower = _actor(borrowerSeed);
        uint256 debt = debtToken.balanceOf(borrower);
        if (debt == 0 || debt > MAX_ACTION_AMOUNT) return;

        address payer = _actor(payerSeed);
        uint256 amount = bound(rawAmount, debt, MAX_ACTION_AMOUNT);
        _mintAndApprove(payer, amount);
        AccountingSnapshot memory before_ = _accountingSnapshot();

        vm.prank(lendingCore);
        uint256 repayment = pool.repay(payer, amount, borrower);

        assertEq(repayment, debt, "an amount at or above the debt did not clear it");
        _assertRepaymentFlow(before_, repayment);
    }

    /// @dev The one action that lowers the share price, so it is not wrapped in `trackSharePrice`.
    function writeOffDebt(uint256 borrowerSeed) external {
        address borrower = _actor(borrowerSeed);
        uint256 debt = debtToken.balanceOf(borrower);
        if (debt == 0) return;

        AccountingSnapshot memory before_ = _accountingSnapshot();
        uint256 totalSupplyBefore = pool.totalSupply();

        vm.prank(lendingCore);
        uint256 writtenOff = pool.writeOffDebt(borrower);

        assertEq(writtenOff, debt, "the whole debt was not written off");
        assertEq(asset.balanceOf(address(pool)), before_.balance, "write-off moved underlying");
        assertEq(debtToken.totalSupply(), before_.debt - writtenOff, "write-off did not retire the debt");
        assertEq(pool.totalAssets(), before_.totalAssets - writtenOff, "write-off did not remove the debt's assets");
        assertEq(pool.totalSupply(), totalSupplyBefore, "write-off moved supply");
    }

    /// @dev Runs one of the other actions from within a flash loan's callback. Not wrapped in `trackSharePrice`, since
    ///      a write-off within the loan lowers the share price; that action asserts its own accounting instead.
    function flashLoan(uint256 actionSeed, uint256 seedA, uint256 seedB, uint256 rawValue, uint256 rawAmount) external {
        (bytes4 action, uint256 maxPayout) = _flashLoanAction(actionSeed, seedA);
        uint256 maxAmount = asset.balanceOf(address(pool)) - maxPayout;
        if (maxAmount == 0) return;

        uint256 amount = bound(rawAmount, 1, maxAmount);
        MockFlashBorrower receiver = new MockFlashBorrower();
        receiver.addCallbackCall(address(this), abi.encodeCall(this.assertLoanMovedOnlyBalance, ()));
        receiver.addCallbackCall(address(this), abi.encodeWithSelector(action, seedA, seedB, rawValue));
        _beforeLoan = _accountingSnapshot();
        _loanAmount = amount;
        uint256 previousTotalAssets = pool.totalAssets();
        uint256 previousTotalSupply = pool.totalSupply();

        pool.flashLoan(receiver, address(asset), amount, "");

        if (action != this.writeOffDebt.selector) {
            _assertSharePriceNotDecreased(previousTotalAssets, previousTotalSupply);
        }
    }

    /// @dev Called from within a flash loan's callback ahead of its inner action.
    function assertLoanMovedOnlyBalance() external view {
        assertEq(asset.balanceOf(address(pool)), _beforeLoan.balance - _loanAmount, "pool not short exactly the loan");
        assertEq(debtToken.totalSupply(), _beforeLoan.debt, "loan moved debt");
        assertEq(pool.totalAssets(), _beforeLoan.totalAssets, "loan moved total assets");
    }

    function _mintAndApprove(address account, uint256 amount) private {
        asset.mint(account, amount);
        vm.prank(account);
        asset.approve(address(pool), amount);
    }

    /// @dev Has the debt token accrue interest on an actor's debt, left pending until the pool next books it. Interest
    ///      accrues on existing debt, so it is capped at 100% of that debt per accrual.
    /// @return Whether any interest was seeded, which it cannot be while there is no debt.
    function _seedInterest(uint256 borrowerSeed, uint256 rawInterest, uint256 rawRetained) private returns (bool) {
        uint256 debt = debtToken.totalSupply();
        if (debt == 0) return false;

        uint256 interest = bound(rawInterest, 1, Math.min(debt, MAX_ACTION_AMOUNT));
        uint256 retained = bound(rawRetained, 0, interest);

        debtToken.seedDebt(_actor(borrowerSeed), interest);
        debtToken.setNextInterest(interest, retained);
        return true;
    }

    function _assertSharePriceNotDecreased(uint256 previousTotalAssets, uint256 previousTotalSupply) private view {
        (uint256 currentHigh, uint256 currentLow) =
            Math.mul512(pool.totalAssets() + ShareMath.VIRTUAL_ASSETS, previousTotalSupply + ShareMath.VIRTUAL_SHARES);
        (uint256 previousHigh, uint256 previousLow) =
            Math.mul512(previousTotalAssets + ShareMath.VIRTUAL_ASSETS, pool.totalSupply() + ShareMath.VIRTUAL_SHARES);

        assertTrue(
            currentHigh > previousHigh || (currentHigh == previousHigh && currentLow >= previousLow),
            "share price decreased"
        );
    }

    function _accountingSnapshot() private view returns (AccountingSnapshot memory snapshot) {
        snapshot.balance = asset.balanceOf(address(pool));
        snapshot.debt = debtToken.totalSupply();
        snapshot.totalAssets = pool.totalAssets();
    }

    function _assertAssetFlow(AccountingSnapshot memory before_, uint256 assetsIn, uint256 assetsOut) private view {
        uint256 expectedBalance = before_.balance + assetsIn;
        uint256 expectedTotalAssets = before_.totalAssets + assetsIn;

        assertGe(expectedBalance, assetsOut);
        assertGe(expectedTotalAssets, assetsOut);
        assertEq(asset.balanceOf(address(pool)), expectedBalance - assetsOut);
        assertEq(debtToken.totalSupply(), before_.debt);
        assertEq(pool.totalAssets(), expectedTotalAssets - assetsOut);
    }

    /// @dev A repayment moves underlying in and retires the same amount of debt, leaving total assets untouched.
    function _assertRepaymentFlow(AccountingSnapshot memory before_, uint256 repayment) private view {
        assertEq(asset.balanceOf(address(pool)), before_.balance + repayment);
        assertEq(debtToken.totalSupply(), before_.debt - repayment);
        assertEq(pool.totalAssets(), before_.totalAssets);
    }

    /// @dev Picks the action a flash loan runs from within its callback.
    function _flashLoanAction(uint256 actionSeed, uint256 ownerSeed)
        private
        view
        returns (bytes4 action, uint256 maxPayout)
    {
        uint256 choice = actionSeed % (writeOffEnabled ? 9 : 8);
        if (choice == 0) return (this.deposit.selector, 0);
        if (choice == 1) return (this.mint.selector, 0);
        if (choice == 2) return (this.withdraw.selector, pool.maxWithdraw(_actor(ownerSeed)));
        if (choice == 3) return (this.redeem.selector, pool.maxWithdraw(_actor(ownerSeed)));
        if (choice == 4) return (this.borrow.selector, pool.idleLiquidity());
        if (choice == 5) return (this.repayPartial.selector, 0);
        if (choice == 6) return (this.repayFull.selector, 0);
        if (choice == 7) return (this.syncInterestRate.selector, 0);
        return (this.writeOffDebt.selector, 0);
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }
}

/// @notice Invariants that hold whether or not debt is written off, run by each campaign below.
// forge-lint: disable-next-line(multi-contract-file)
abstract contract BorrowablePoolInvariantsBase is Test {
    uint256 internal constant SEED_POSITION_ASSETS = 1000e18;
    uint256 internal constant SEED_DEBT = 500e18;
    /// @dev Deliberately not a round number, so a donation cannot divide cleanly into the share base.
    uint256 internal constant SEED_DONATION = 333e18 + 1;

    BorrowablePool internal pool;
    MockERC20 internal asset;
    MockDebtToken internal debtToken;
    BorrowablePoolHandler internal handler;
    address[] internal actors;

    /// @param writeOffEnabled Whether the handler may write off debt, directly or within a flash loan.
    function _setUp(bool writeOffEnabled) internal {
        address lendingCore = makeAddr("lendingCore");
        address flashLoanConfigurator = makeAddr("flashLoanConfigurator");
        address[] memory actorList = new address[](3);
        for (uint256 i; i < actorList.length; i++) {
            actorList[i] = makeAddr(string.concat("actor", vm.toString(i)));
            actors.push(actorList[i]);
        }

        asset = new MockERC20();
        // The fee recipients are actors, so claimed fee shares go on to take part in later actions.
        MockOnlendFeeRegistry feeRegistry = new MockOnlendFeeRegistry(actorList[1]);
        BorrowablePool poolImplementation = new BorrowablePool();
        pool = BorrowablePool(Clones.clone(address(poolImplementation)));

        debtToken = new MockDebtToken(address(pool), asset.decimals());
        pool.initialize(
            makeAddr("defaultAdmin"),
            makeAddr("hookUpdater"),
            flashLoanConfigurator,
            makeAddr("operatorFeeConfigurator"),
            address(0),
            0,
            0,
            lendingCore,
            true,
            asset,
            "fOnlend USD Coin",
            "fOnlend USDC",
            address(debtToken),
            address(feeRegistry),
            actorList[0]
        );

        _mintAndApprove(actorList[0], SEED_POSITION_ASSETS);
        vm.prank(actorList[0]);
        pool.deposit(SEED_POSITION_ASSETS, actorList[0]);

        vm.prank(lendingCore);
        pool.borrow(actorList[2], SEED_DEBT, actorList[2]);

        asset.mint(address(pool), SEED_DONATION);

        handler =
            new BorrowablePoolHandler(pool, asset, debtToken, feeRegistry, lendingCore, actorList, writeOffEnabled);

        targetContract(address(handler));
        bytes4[] memory excluded = new bytes4[](writeOffEnabled ? 1 : 2);
        excluded[0] = handler.assertLoanMovedOnlyBalance.selector;
        if (!writeOffEnabled) excluded[1] = handler.writeOffDebt.selector;
        excludeSelector(FuzzSelector({addr: address(handler), selectors: excluded}));
    }

    /// @dev Pool-held shares consist exactly of the shares donated through the handler, the pool issuing no
    ///      collateral positions of its own.
    function invariant_PoolShareBalanceMatchesDonations() public view {
        assertEq(pool.balanceOf(address(pool)), handler.donatedShares());
    }

    /// @dev Total supply exceeds the shares held by accounts by exactly the operator and Onlend fee shares no account
    ///      holds yet. The fee recipients are actors, so shares already claimed are among those held.
    function invariant_TotalSupplyExceedsHeldSharesByFeeShares() public view {
        uint256 heldShares = pool.balanceOf(address(pool));
        for (uint256 i; i < actors.length; i++) {
            heldShares += pool.balanceOf(actors[i]);
        }

        assertEq(pool.totalSupply(), heldShares + pool.totalOperatorFeeShares() + pool.totalOnlendFeeShares());
    }

    /// @dev Neither deposits nor fee shares can take the supply past what a conversion can price against.
    function invariant_TotalSupplyNeverExceedsMaxTotalShares() public view {
        assertLe(pool.totalSupply(), ShareMath.MAX_TOTAL_SHARES);
    }

    /// @dev The underlying the pool holds is exactly what it has accounted for plus the donations it ignores, so no
    ///      operation books liquidity the pool never received and none goes missing.
    function invariant_PoolBalanceMatchesAccountedLiquidityAndDonations() public view {
        assertEq(asset.balanceOf(address(pool)), pool.idleLiquidity() + SEED_DONATION + handler.donatedAssets());
    }

    function _mintAndApprove(address account, uint256 amount) private {
        asset.mint(account, amount);
        vm.prank(account);
        asset.approve(address(pool), amount);
    }
}

// forge-lint: disable-next-line(multi-contract-file)
contract BorrowablePoolWithoutWriteOffInvariantsTest is BorrowablePoolInvariantsBase {
    function setUp() public {
        _setUp(false);
    }

    /// @dev The shares outstanding must never claim more underlying than the pool holds. Asserted on the asset and
    ///      share bases themselves rather than through `previewRedeem`, which would confirm the conversion against
    ///      itself and pass on any conversion that understates what a share is worth. Holds only without write-offs,
    ///      the one operation that can take the share price below one.
    function invariant_SharesNeverClaimMoreThanTotalAssets() public view {
        assertGe(pool.totalAssets() + ShareMath.VIRTUAL_ASSETS, pool.totalSupply() + ShareMath.VIRTUAL_SHARES);
    }
}

// forge-lint: disable-next-line(multi-contract-file)
contract BorrowablePoolWithWriteOffInvariantsTest is BorrowablePoolInvariantsBase {
    function setUp() public {
        _setUp(true);
    }
}
