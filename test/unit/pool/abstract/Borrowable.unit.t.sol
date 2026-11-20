// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {IHookReceiver, Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {BasePool} from "src/pool/abstract/BasePool.sol";
import {Borrowable} from "src/pool/abstract/Borrowable.sol";
import {IDebtToken} from "src/pool/debt/interfaces/IDebtToken.sol";
import {IBorrowable} from "src/pool/interfaces/IBorrowable.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {IOnlendFeeRegistry} from "src/pool/interfaces/IOnlendFeeRegistry.sol";
import {ShareMath} from "src/pool/lib/ShareMath.sol";
import {MockHookReceiver} from "../../hooks/mocks/MockHookReceiver.sol";
import {MockDebtToken} from "../mocks/MockDebtToken.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockFlashBorrower} from "../mocks/MockFlashBorrower.sol";
import {MockOnlendFeeRegistry} from "../mocks/MockOnlendFeeRegistry.sol";
import {BorrowableHarness} from "./mocks/BorrowableHarness.sol";

contract BorrowableUnitTest is Test {
    BorrowableHarness internal pool;
    MockERC20 internal asset;
    MockDebtToken internal debtToken;
    MockOnlendFeeRegistry internal feeRegistry;
    MockHookReceiver internal hookReceiver;

    address internal defaultAdmin = makeAddr("defaultAdmin");
    address internal hookUpdater = makeAddr("hookUpdater");
    address internal flashLoanConfigurator = makeAddr("flashLoanConfigurator");
    address internal operatorFeeConfigurator = makeAddr("operatorFeeConfigurator");
    address internal operatorFeeRecipient = makeAddr("operatorFeeRecipient");
    address internal onlendFeeRecipient = makeAddr("onlendFeeRecipient");
    address internal lendingCore = makeAddr("lendingCore");
    address internal caller = makeAddr("caller");
    address internal receiver = makeAddr("receiver");
    address internal other = makeAddr("other");
    address internal borrower = makeAddr("borrower");
    address internal operator = makeAddr("operator");

    string internal constant POOL_NAME = "fOnlend USD Coin";
    string internal constant POOL_SYMBOL = "fOnlend USDC";
    string internal constant DEBT_TOKEN_NAME = "dOnlend USD Coin";
    string internal constant DEBT_TOKEN_SYMBOL = "dOnlend USDC";

    uint256 internal constant IDLE_LIQUIDITY = 1000e18;
    uint256 internal constant TOTAL_DEBT = 500e18;
    uint256 internal constant DEPOSIT_ASSETS = 1000;
    uint256 internal constant MINT_SHARES = 1000;
    uint256 internal constant EXIT_POSITION_ASSETS = 1000;
    uint256 internal constant EXIT_POSITION_SHARES = 1000;
    uint256 internal constant WITHDRAW_ASSETS = 400;
    uint256 internal constant REDEEM_SHARES = 400;
    uint256 internal constant TRANSFER_POSITION_SHARES = 1000;
    uint256 internal constant TRANSFER_SHARES = 400;
    uint256 internal constant BORROW_LIQUIDITY = 1000;
    uint256 internal constant BORROW_AMOUNT = 400;
    uint256 internal constant REPAY_IDLE_LIQUIDITY = 1000;
    uint256 internal constant REPAY_DEBT = 600;
    uint256 internal constant REPAY_AMOUNT = 400;
    uint256 internal constant WRITE_OFF_IDLE_LIQUIDITY = 1_000_000;
    uint256 internal constant WRITE_OFF_DEBT = 2_000_000;
    uint256 internal constant WRITE_OFF_DEPOSITOR_SHARES = 3_000_000;
    uint256 internal constant MAX_DEPOSIT_ROOM = 1000;
    uint16 internal constant FIXED_FEE_BPS = 1000;
    uint16 internal constant SPLIT_FEE_BPS = 2500;

    function setUp() public {
        asset = new MockERC20();
        hookReceiver = new MockHookReceiver();
        feeRegistry = new MockOnlendFeeRegistry(onlendFeeRecipient);
        BorrowableHarness implementation = new BorrowableHarness();
        pool = BorrowableHarness(Clones.clone(address(implementation)));
        debtToken = new MockDebtToken(address(pool), asset.decimals());
        pool.initialize(
            defaultAdmin,
            hookUpdater,
            flashLoanConfigurator,
            operatorFeeConfigurator,
            address(0),
            0,
            0,
            lendingCore,
            true,
            asset,
            POOL_NAME,
            POOL_SYMBOL,
            address(debtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );
    }

    // _initializeBorrowable()

    function test_initializeBorrowable_GrantsOperatorFeeConfigRole() public view {
        assertTrue(pool.hasRole(pool.OPERATOR_FEE_CONFIG_ROLE(), operatorFeeConfigurator));
    }

    function test_initializeBorrowable_AllowsZeroAddressOperatorFeeConfigurator() public {
        BorrowableHarness rolelessPool = BorrowableHarness(Clones.clone(address(new BorrowableHarness())));
        MockDebtToken testDebtToken = new MockDebtToken(address(rolelessPool), asset.decimals());

        rolelessPool.initialize(
            defaultAdmin,
            hookUpdater,
            address(0),
            address(0),
            address(0),
            0,
            0,
            lendingCore,
            false,
            asset,
            POOL_NAME,
            POOL_SYMBOL,
            address(testDebtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );

        assertEq(rolelessPool.getRoleMemberCount(rolelessPool.OPERATOR_FEE_CONFIG_ROLE()), 0);
    }

    function test_initializeBorrowable_ConfiguresPoolShareTokenAndUnderlying() public view {
        assertEq(pool.name(), POOL_NAME);
        assertEq(pool.symbol(), POOL_SYMBOL);
        assertEq(pool.decimals(), asset.decimals());
        assertEq(pool.asset(), address(asset));
    }

    function test_initializeBorrowable_StoresDebtToken() public view {
        assertEq(pool.debtToken(), address(debtToken));
    }

    function test_initializeBorrowable_StoresFeeRegistry() public view {
        assertEq(pool.feeRegistry(), address(feeRegistry));
    }

    function test_initializeBorrowable_ReadsOnlendFeeConfig() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);

        (BorrowableHarness testPool,) = _deployBorrowableHarness();

        (uint16 fixedFeeBps, uint16 splitFeeBps) = testPool.onlendFeeConfig();
        assertEq(fixedFeeBps, FIXED_FEE_BPS);
        assertEq(splitFeeBps, SPLIT_FEE_BPS);
    }

    function test_initializeBorrowable_SetsOperatorFeeRecipient() public view {
        assertEq(pool.operatorFeeRecipient(), operatorFeeRecipient);
    }

    function test_initializeBorrowable_RevertsWhenDebtTokenIsInvalid() public {
        address invalidDebtToken = makeAddr("invalidDebtToken");
        BorrowableHarness instance = BorrowableHarness(Clones.clone(address(new BorrowableHarness())));

        vm.expectRevert(abi.encodeWithSelector(Borrowable.InvalidDebtToken.selector, invalidDebtToken));
        instance.initialize(
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
            POOL_NAME,
            POOL_SYMBOL,
            invalidDebtToken,
            address(feeRegistry),
            operatorFeeRecipient
        );
    }

    function test_initializeBorrowable_RevertsWhenDebtTokenDecimalsDoNotMatchPoolShares() public {
        BorrowableHarness instance = BorrowableHarness(Clones.clone(address(new BorrowableHarness())));
        MockDebtToken mismatchedDebtToken = new MockDebtToken(address(instance), 6);

        vm.expectRevert(
            abi.encodeWithSelector(BasePool.InvalidTokenDecimals.selector, address(mismatchedDebtToken), 6, 18)
        );
        instance.initialize(
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
            POOL_NAME,
            POOL_SYMBOL,
            address(mismatchedDebtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );
    }

    function test_initializeBorrowable_RevertsWhenFeeRegistryIsInvalid() public {
        BorrowableHarness instance = BorrowableHarness(Clones.clone(address(new BorrowableHarness())));
        MockDebtToken testDebtToken = new MockDebtToken(address(instance), asset.decimals());
        feeRegistry.setSupportsInterfaceOverride(false);

        vm.expectRevert(abi.encodeWithSelector(Borrowable.InvalidFeeRegistry.selector, address(feeRegistry)));
        instance.initialize(
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
            POOL_NAME,
            POOL_SYMBOL,
            address(testDebtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );
    }

    // syncInterestRate()

    function test_syncInterestRate_UpdatesIndexesBeforeRates() public {
        _seedIdleLiquidity(pool, IDLE_LIQUIDITY);

        vm.expectCall(address(debtToken), abi.encodeCall(IDebtToken.accrueInterest, ()), 1);
        vm.expectCall(address(debtToken), abi.encodeCall(IDebtToken.updateBorrowRates, (IDLE_LIQUIDITY)), 1);
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.UpdateBorrowRatesCalled(IDLE_LIQUIDITY);

        vm.prank(caller);
        pool.syncInterestRate();
    }

    // syncAccount()

    function test_syncAccount_SynchronizesSpecifiedAccountAndRefreshesRatesInOrder() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_SYNC_ACCOUNT;
        bytes memory hookData = abi.encode(borrower);
        _seedIdleLiquidity(pool, IDLE_LIQUIDITY);
        _configureHooks(actionBit, actionBit);

        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(IHookReceiver.onHook, (address(pool), Phase.BEFORE, ActionLib.POOL_SYNC_ACCOUNT, hookData)),
            1
        );
        vm.expectCall(address(debtToken), abi.encodeCall(IDebtToken.accrueInterest, ()), 1);
        vm.expectCall(address(debtToken), abi.encodeCall(IDebtToken.syncAccount, (borrower)), 1);
        vm.expectCall(address(debtToken), abi.encodeCall(IDebtToken.updateBorrowRates, (IDLE_LIQUIDITY)), 1);
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(IHookReceiver.onHook, (address(pool), Phase.AFTER, ActionLib.POOL_SYNC_ACCOUNT, hookData)),
            1
        );
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(address(pool), Phase.BEFORE, ActionLib.POOL_SYNC_ACCOUNT, hookData);
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.SyncAccountCalled(borrower);
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.UpdateBorrowRatesCalled(IDLE_LIQUIDITY);
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(address(pool), Phase.AFTER, ActionLib.POOL_SYNC_ACCOUNT, hookData);

        vm.prank(caller);
        pool.syncAccount(borrower);
    }

    function test_syncAccount_RevertsWhenBeforeHookRejectsSync() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_SYNC_ACCOUNT;
        _configureHooks(actionBit, 0);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(caller);
        pool.syncAccount(borrower);
    }

    function test_syncAccount_RevertsWhenAfterHookRejectsSync() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_SYNC_ACCOUNT;
        _configureHooks(0, actionBit);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(caller);
        pool.syncAccount(borrower);
    }

    // claimFeeShares()

    function test_claimFeeShares_MintsEachBucketToItsRecipient() public {
        pool.seedOperatorFeeShares(60);
        pool.seedOnlendFeeShares(40);

        vm.prank(caller);
        pool.claimFeeShares();

        assertEq(pool.balanceOf(operatorFeeRecipient), 60);
        assertEq(pool.balanceOf(onlendFeeRecipient), 40);
        assertEq(pool.totalOperatorFeeShares(), 0);
        assertEq(pool.totalOnlendFeeShares(), 0);
    }

    function test_claimFeeShares_ReturnsClaimedShares() public {
        pool.seedOperatorFeeShares(60);
        pool.seedOnlendFeeShares(40);

        vm.prank(caller);
        (uint256 operatorFeeShares, uint256 onlendFeeShares) = pool.claimFeeShares();

        assertEq(operatorFeeShares, 60);
        assertEq(onlendFeeShares, 40);
    }

    /// @dev The shares were already counted by `totalSupply`, so claiming them dilutes nobody.
    function test_claimFeeShares_DoesNotChangeTotalSupply() public {
        pool.seedShares(caller, 1000);
        pool.seedOperatorFeeShares(60);
        pool.seedOnlendFeeShares(40);

        vm.prank(caller);
        pool.claimFeeShares();

        assertEq(pool.totalSupply(), 1100);
    }

    function test_claimFeeShares_MintsOnlyOperatorFeeSharesWhenNoOnlendFeeSharesAccrued() public {
        pool.seedOperatorFeeShares(60);

        vm.prank(caller);
        pool.claimFeeShares();

        assertEq(pool.balanceOf(operatorFeeRecipient), 60);
        assertEq(pool.balanceOf(onlendFeeRecipient), 0);
    }

    function test_claimFeeShares_MintsOnlyOnlendFeeSharesWhenNoOperatorFeeSharesAccrued() public {
        pool.seedOnlendFeeShares(40);

        vm.prank(caller);
        pool.claimFeeShares();

        assertEq(pool.balanceOf(operatorFeeRecipient), 0);
        assertEq(pool.balanceOf(onlendFeeRecipient), 40);
    }

    function test_claimFeeShares_MintsToCurrentOperatorFeeRecipient() public {
        pool.seedOperatorFeeShares(60);
        vm.prank(operatorFeeConfigurator);
        pool.setOperatorFeeRecipient(other);

        vm.prank(caller);
        pool.claimFeeShares();

        assertEq(pool.balanceOf(other), 60);
        assertEq(pool.balanceOf(operatorFeeRecipient), 0);
    }

    function test_claimFeeShares_MintsToCurrentOnlendFeeRecipient() public {
        pool.seedOnlendFeeShares(40);
        feeRegistry.setFeeRecipient(other);

        vm.prank(caller);
        pool.claimFeeShares();

        assertEq(pool.balanceOf(other), 40);
        assertEq(pool.balanceOf(onlendFeeRecipient), 0);
    }

    function test_claimFeeShares_EmitsFeeSharesClaimed() public {
        pool.seedOperatorFeeShares(60);
        pool.seedOnlendFeeShares(40);

        vm.expectEmit(address(pool));
        emit Borrowable.FeeSharesClaimed(caller, operatorFeeRecipient, onlendFeeRecipient, 60, 40);
        vm.prank(caller);
        pool.claimFeeShares();
    }

    function test_claimFeeShares_ClaimsFeesAccruedByTheCall() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        // 1,000 of the assets back the 1,000 shares already counted, so the 30 of fees buy shares one for one.
        _seedIdleLiquidity(testPool, 1030);
        // Of 100 accrued with 20 retained, Onlend takes a 10 fixed fee and 5 of the retention, leaving 15 to the
        // operator.
        testDebtToken.setNextInterest(100, 20);

        vm.prank(caller);
        testPool.claimFeeShares();

        assertEq(testPool.balanceOf(operatorFeeRecipient), 15);
        assertEq(testPool.balanceOf(onlendFeeRecipient), 15);
    }

    function test_claimFeeShares_ExecutesHooksAroundClaimInOrder() public {
        pool.seedOperatorFeeShares(60);
        pool.seedOnlendFeeShares(40);
        uint256 actionBit = uint256(1) << ActionLib.POOL_CLAIM_FEE_SHARES;
        _configureHooks(actionBit, actionBit);
        bytes memory beforeData = abi.encode(caller, operatorFeeRecipient, onlendFeeRecipient);
        bytes memory afterData = abi.encode(caller, operatorFeeRecipient, onlendFeeRecipient, uint256(60), uint256(40));

        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(address(pool), Phase.BEFORE, ActionLib.POOL_CLAIM_FEE_SHARES, beforeData);
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(pool));
        emit IERC20.Transfer(address(0), operatorFeeRecipient, 60);
        vm.expectEmit(address(pool));
        emit IERC20.Transfer(address(0), onlendFeeRecipient, 40);
        vm.expectEmit(address(pool));
        emit Borrowable.FeeSharesClaimed(caller, operatorFeeRecipient, onlendFeeRecipient, 60, 40);
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(address(pool), Phase.AFTER, ActionLib.POOL_CLAIM_FEE_SHARES, afterData);

        vm.prank(caller);
        pool.claimFeeShares();

        assertEq(hookReceiver.calls(), 2);
    }

    function test_claimFeeShares_RevertsWhenNoFeeSharesAccrued() public {
        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(caller);
        pool.claimFeeShares();
    }

    function test_claimFeeShares_RevertsWhenBeforeHookRejectsClaim() public {
        pool.seedOperatorFeeShares(60);
        uint256 actionBit = uint256(1) << ActionLib.POOL_CLAIM_FEE_SHARES;
        _configureHooks(actionBit, 0);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(caller);
        pool.claimFeeShares();
    }

    function test_claimFeeShares_RevertsWhenAfterHookRejectsClaim() public {
        pool.seedOperatorFeeShares(60);
        uint256 actionBit = uint256(1) << ActionLib.POOL_CLAIM_FEE_SHARES;
        _configureHooks(0, actionBit);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(caller);
        pool.claimFeeShares();
    }

    // setOperatorFeeRecipient()

    function test_setOperatorFeeRecipient_SetsOperatorFeeRecipient() public {
        vm.prank(operatorFeeConfigurator);
        pool.setOperatorFeeRecipient(other);

        assertEq(pool.operatorFeeRecipient(), other);
    }

    function test_setOperatorFeeRecipient_EmitsOperatorFeeRecipientSet() public {
        vm.expectEmit(address(pool));
        emit Borrowable.OperatorFeeRecipientSet(other);
        vm.prank(operatorFeeConfigurator);
        pool.setOperatorFeeRecipient(other);
    }

    function test_setOperatorFeeRecipient_RevertsWhenRecipientIsZero() public {
        vm.expectRevert(Borrowable.InvalidOperatorFeeRecipient.selector);
        vm.prank(operatorFeeConfigurator);
        pool.setOperatorFeeRecipient(address(0));
    }

    function test_setOperatorFeeRecipient_RevertsWhenCallerIsNotOperatorFeeConfigurator() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, pool.OPERATOR_FEE_CONFIG_ROLE()
            )
        );
        vm.prank(caller);
        pool.setOperatorFeeRecipient(other);
    }

    // debtToken()

    function test_debtToken_ReturnsAssociatedDebtToken() public view {
        assertEq(pool.debtToken(), address(debtToken));
    }

    // idleLiquidity()

    /// @dev Underlying arriving without a pool operation behind it is the lever an inflation attack pulls. The pool
    ///      accounts for what its own operations move, so a donation leaves it holding more than it counts.
    function test_idleLiquidity_ExcludesDonatedUnderlying() public {
        _mintAndApprove(pool, caller, DEPOSIT_ASSETS);
        vm.prank(caller);
        pool.deposit(DEPOSIT_ASSETS, receiver);

        asset.mint(address(pool), 1e6);

        assertEq(pool.idleLiquidity(), DEPOSIT_ASSETS);
        assertEq(asset.balanceOf(address(pool)), DEPOSIT_ASSETS + 1e6);
    }

    // totalOperatorFeeShares()

    function test_totalOperatorFeeShares_ReturnsZeroWhenNothingHasAccrued() public view {
        assertEq(pool.totalOperatorFeeShares(), 0);
    }

    /// @dev `claimFeeShares` accrues before minting, so the operator's fee on interest the debt token holds but has not
    ///      handed over is already claimable.
    function test_totalOperatorFeeShares_IncludesSharesOwedOnPendingInterest() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        testPool.seedOperatorFeeShares(40);
        // 1,040 of the assets back the 1,040 shares already counted; the remaining 30 is fees on interest not yet
        // handed over, so they buy shares one for one.
        _seedIdleLiquidity(testPool, 1070);

        // Of 100 accrued with 20 retained, the operator keeps 15 after Onlend's 10 fixed fee and 5 of the retention.
        testDebtToken.setNextInterest(100, 20);

        assertEq(testPool.totalOperatorFeeShares(), 55);
    }

    // totalOnlendFeeShares()

    function test_totalOnlendFeeShares_ReturnsZeroWhenNothingHasAccrued() public view {
        assertEq(pool.totalOnlendFeeShares(), 0);
    }

    /// @dev `claimFeeShares` accrues before minting, so Onlend's fee on interest the debt token holds but has not
    ///      handed over is already claimable.
    function test_totalOnlendFeeShares_IncludesSharesOwedOnPendingInterest() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        testPool.seedOnlendFeeShares(40);
        // 1,040 of the assets back the 1,040 shares already counted; the remaining 30 is fees on interest not yet
        // handed over, so they buy shares one for one.
        _seedIdleLiquidity(testPool, 1070);

        // Of 100 accrued with 20 retained, Onlend takes a 10 fixed fee and 5 of the retention.
        testDebtToken.setNextInterest(100, 20);

        assertEq(testPool.totalOnlendFeeShares(), 55);
    }

    // depositInterestRate()

    /// @dev The virtual shares take the same cut of an incoming yield as they do of the assets backing it, so the
    ///      rate a shareholder earns is the yield over the asset base including the virtual assets.
    function test_depositInterestRate_ReturnsYieldOverAssetsIncludingVirtualAssets() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        _seedIdleLiquidity(testPool, 1e6);
        testDebtToken.seedDebt(borrower, 1e6);
        testDebtToken.setAnnualInterest(150_000, 0);

        // 150,000 yield / (1,000,000 idle + 1,000,000 debt + 1,000,000 virtual) = 5%.
        assertEq(testPool.depositInterestRate(), 0.05e18);
    }

    function test_depositInterestRate_ReturnsRateWhenAllLiquidityIsBorrowed() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testDebtToken.seedDebt(borrower, 2e6);
        testDebtToken.setAnnualInterest(150_000, 0);

        // 150,000 yield / (2,000,000 debt + 1,000,000 virtual) = 5%.
        assertEq(testPool.depositInterestRate(), 0.05e18);
    }

    function test_depositInterestRate_ExcludesOperatorAndOnlendFees() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        _seedIdleLiquidity(testPool, 1e6);
        testDebtToken.seedDebt(borrower, 1e6);
        testDebtToken.setAnnualInterest(200_000, 30_000);

        // 200,000 interest less 30,000 retained and a 20,000 fixed fee leaves 150,000 yield, over 3,000,000 = 5%.
        assertEq(testPool.depositInterestRate(), 0.05e18);
    }

    function test_depositInterestRate_ReturnsZeroWhenInterestIsZero() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        _seedIdleLiquidity(testPool, 1e6);
        testDebtToken.setAnnualInterest(0, 0);

        assertEq(testPool.depositInterestRate(), 0);
    }

    // deposit()

    function test_deposit_TransfersAssetsFromCallerToPool() public {
        _mintAndApprove(pool, caller, DEPOSIT_ASSETS);

        vm.prank(caller);
        pool.deposit(DEPOSIT_ASSETS, receiver);

        assertEq(asset.balanceOf(caller), 0);
        assertEq(asset.balanceOf(address(pool)), DEPOSIT_ASSETS);
    }

    function test_deposit_BooksAssetsAsIdleLiquidity() public {
        _mintAndApprove(pool, caller, DEPOSIT_ASSETS);

        vm.prank(caller);
        pool.deposit(DEPOSIT_ASSETS, receiver);

        assertEq(pool.idleLiquidity(), DEPOSIT_ASSETS);
    }

    function test_deposit_ReturnsTheAmountOfSharesReceived() public {
        _mintAndApprove(pool, caller, DEPOSIT_ASSETS);

        vm.prank(caller);
        uint256 shares = pool.deposit(DEPOSIT_ASSETS, receiver);

        assertEq(shares, DEPOSIT_ASSETS);
        assertEq(pool.balanceOf(receiver), shares);
    }

    function test_deposit_ExecutesHooksAndInterestAccountingInOrder() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_DEPOSIT;
        _mintAndApprove(pool, caller, DEPOSIT_ASSETS);
        _configureHooks(actionBit, actionBit);

        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(
            address(pool), Phase.BEFORE, ActionLib.POOL_DEPOSIT, abi.encode(receiver, caller, caller, DEPOSIT_ASSETS)
        );
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(pool));
        emit IERC4626.Deposit(caller, receiver, DEPOSIT_ASSETS, DEPOSIT_ASSETS);
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.UpdateBorrowRatesCalled(DEPOSIT_ASSETS);
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(
            address(pool),
            Phase.AFTER,
            ActionLib.POOL_DEPOSIT,
            abi.encode(receiver, caller, caller, DEPOSIT_ASSETS, DEPOSIT_ASSETS)
        );

        vm.prank(caller);
        pool.deposit(DEPOSIT_ASSETS, receiver);
    }

    function test_deposit_PricesSharesUsingOutstandingDebt() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(other, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);
        _mintAndApprove(testPool, caller, 200);

        vm.prank(caller);
        uint256 shares = testPool.deposit(200, receiver);

        // 1,000,000 shares against 3,000,000 assets, each side lifted by the virtual pair, prices the
        // pool at exactly 4,000,000 / 2,000,000 = two assets per share.
        assertEq(shares, 100);
    }

    function test_deposit_AcceptsMinimumAmountThatMintsOneShare() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(other, 1);
        testDebtToken.seedDebt(borrower, 3);
        _mintAndApprove(testPool, caller, 2);

        vm.prank(caller);
        uint256 shares = testPool.deposit(2, receiver);

        // floor(2 assets * 1,000,001 adjusted shares / 1,000,003 adjusted assets) = 1 share.
        assertEq(shares, 1);
    }

    function test_deposit_AcceptsAssetsWhoseSharesReachMaxDepositShares() public {
        BorrowableHarness testPool = _deployMaxDepositRoomPosition();
        _mintAndApprove(testPool, caller, MAX_DEPOSIT_ROOM);

        vm.prank(caller);
        testPool.deposit(MAX_DEPOSIT_ROOM, receiver);

        assertEq(testPool.totalSupply(), ShareMath.MAX_DEPOSIT_SHARES);
    }

    function test_deposit_RevertsWhenSharesWouldExceedMaxDepositShares() public {
        BorrowableHarness testPool = _deployMaxDepositRoomPosition();
        _mintAndApprove(testPool, caller, MAX_DEPOSIT_ROOM + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxDeposit.selector, receiver, MAX_DEPOSIT_ROOM + 1, MAX_DEPOSIT_ROOM
            )
        );
        vm.prank(caller);
        testPool.deposit(MAX_DEPOSIT_ROOM + 1, receiver);
    }

    function test_deposit_RevertsWhenAssetsAreZero() public {
        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(caller);
        pool.deposit(0, receiver);
    }

    function test_deposit_RevertsWhenPositiveAssetsWouldMintZeroShares() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(other, 1);
        testDebtToken.seedDebt(borrower, 3);

        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(caller);
        testPool.deposit(1, receiver);
    }

    function test_deposit_RecomputesBorrowRatesOnUpdatedIdleLiquidity() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(other, 1000);
        _seedIdleLiquidity(testPool, 500);
        testDebtToken.seedDebt(borrower, 500);
        _mintAndApprove(testPool, caller, DEPOSIT_ASSETS);

        // The 500 already idle plus the 1,000 deposited.
        vm.expectCall(address(testDebtToken), abi.encodeCall(IDebtToken.updateBorrowRates, (1500)), 1);
        vm.prank(caller);
        testPool.deposit(DEPOSIT_ASSETS, receiver);
    }

    function test_deposit_FiresBeforeHookWithDepositData() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_DEPOSIT;
        _mintAndApprove(pool, caller, DEPOSIT_ASSETS);
        _configureHooks(actionBit, 0);

        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (
                    address(pool),
                    Phase.BEFORE,
                    ActionLib.POOL_DEPOSIT,
                    abi.encode(receiver, caller, caller, DEPOSIT_ASSETS)
                )
            ),
            1
        );

        vm.prank(caller);
        pool.deposit(DEPOSIT_ASSETS, receiver);
    }

    function test_deposit_FiresAfterHookWithDepositResult() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        uint256 actionBit = uint256(1) << ActionLib.POOL_DEPOSIT;
        testPool.seedShares(other, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);
        _mintAndApprove(testPool, caller, 200);
        _configureHooks(testPool, 0, actionBit);

        // Two assets per share, so 200 assets buy 100 shares.
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (
                    address(testPool),
                    Phase.AFTER,
                    ActionLib.POOL_DEPOSIT,
                    abi.encode(receiver, caller, caller, uint256(200), uint256(100))
                )
            ),
            1
        );

        vm.prank(caller);
        testPool.deposit(200, receiver);
    }

    function test_deposit_RevertsWhenBeforeHookRejectsDeposit() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_DEPOSIT;
        _configureHooks(actionBit, 0);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(caller);
        pool.deposit(DEPOSIT_ASSETS, receiver);
    }

    function test_deposit_RevertsWhenAfterHookRejectsDeposit() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_DEPOSIT;
        _mintAndApprove(pool, caller, DEPOSIT_ASSETS);
        _configureHooks(0, actionBit);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(caller);
        pool.deposit(DEPOSIT_ASSETS, receiver);
    }

    // mint()

    function test_mint_TransfersRequiredAssetsFromCallerToPool() public {
        _mintAndApprove(pool, caller, MINT_SHARES);

        vm.prank(caller);
        pool.mint(MINT_SHARES, receiver);

        assertEq(asset.balanceOf(caller), 0);
        assertEq(asset.balanceOf(address(pool)), MINT_SHARES);
    }

    function test_mint_BooksAssetsAsIdleLiquidity() public {
        _mintAndApprove(pool, caller, MINT_SHARES);

        vm.prank(caller);
        pool.mint(MINT_SHARES, receiver);

        assertEq(pool.idleLiquidity(), MINT_SHARES);
    }

    function test_mint_MintsRequestedSharesToReceiver() public {
        _mintAndApprove(pool, caller, MINT_SHARES);

        vm.prank(caller);
        pool.mint(MINT_SHARES, receiver);

        assertEq(pool.balanceOf(receiver), MINT_SHARES);
    }

    function test_mint_ReturnsTheAmountOfAssetsRequired() public {
        _mintAndApprove(pool, caller, MINT_SHARES);

        vm.prank(caller);
        uint256 assets = pool.mint(MINT_SHARES, receiver);

        assertEq(assets, MINT_SHARES);
    }

    function test_mint_ExecutesHooksAndInterestAccountingInOrder() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_MINT;
        _mintAndApprove(pool, caller, MINT_SHARES);
        _configureHooks(actionBit, actionBit);

        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(
            address(pool), Phase.BEFORE, ActionLib.POOL_MINT, abi.encode(receiver, caller, caller, MINT_SHARES)
        );
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(pool));
        emit IERC4626.Deposit(caller, receiver, MINT_SHARES, MINT_SHARES);
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.UpdateBorrowRatesCalled(MINT_SHARES);
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(
            address(pool),
            Phase.AFTER,
            ActionLib.POOL_MINT,
            abi.encode(receiver, caller, caller, MINT_SHARES, MINT_SHARES)
        );

        vm.prank(caller);
        pool.mint(MINT_SHARES, receiver);
    }

    function test_mint_PricesAssetsUsingOutstandingDebt() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(other, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);
        _mintAndApprove(testPool, caller, 200);

        vm.prank(caller);
        uint256 assets = testPool.mint(100, receiver);

        // 1,000,000 shares against 3,000,000 assets, each side lifted by the virtual pair, prices the
        // pool at exactly 4,000,000 / 2,000,000 = two assets per share.
        assertEq(assets, 200);
    }

    function test_mint_AcceptsSharesReachingMaxDepositShares() public {
        BorrowableHarness testPool = _deployMaxDepositRoomPosition();
        _mintAndApprove(testPool, caller, MAX_DEPOSIT_ROOM);

        vm.prank(caller);
        testPool.mint(MAX_DEPOSIT_ROOM, receiver);

        assertEq(testPool.totalSupply(), ShareMath.MAX_DEPOSIT_SHARES);
    }

    function test_mint_RevertsWhenSharesWouldExceedMaxDepositShares() public {
        BorrowableHarness testPool = _deployMaxDepositRoomPosition();
        _mintAndApprove(testPool, caller, MAX_DEPOSIT_ROOM + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxMint.selector, receiver, MAX_DEPOSIT_ROOM + 1, MAX_DEPOSIT_ROOM
            )
        );
        vm.prank(caller);
        testPool.mint(MAX_DEPOSIT_ROOM + 1, receiver);
    }

    function test_mint_RevertsWhenSharesAreZero() public {
        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(caller);
        pool.mint(0, receiver);
    }

    function test_mint_RecomputesBorrowRatesOnUpdatedIdleLiquidity() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(other, 1000);
        _seedIdleLiquidity(testPool, 500);
        testDebtToken.seedDebt(borrower, 500);
        _mintAndApprove(testPool, caller, MINT_SHARES);

        // 1,000 assets back 1,000 shares, so the 500 already idle plus the 1,000 the mint costs.
        vm.expectCall(address(testDebtToken), abi.encodeCall(IDebtToken.updateBorrowRates, (1500)), 1);
        vm.prank(caller);
        testPool.mint(MINT_SHARES, receiver);
    }

    function test_mint_FiresBeforeHookWithMintData() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_MINT;
        _mintAndApprove(pool, caller, MINT_SHARES);
        _configureHooks(actionBit, 0);

        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (address(pool), Phase.BEFORE, ActionLib.POOL_MINT, abi.encode(receiver, caller, caller, MINT_SHARES))
            ),
            1
        );

        vm.prank(caller);
        pool.mint(MINT_SHARES, receiver);
    }

    function test_mint_FiresAfterHookWithMintResult() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        uint256 actionBit = uint256(1) << ActionLib.POOL_MINT;
        testPool.seedShares(other, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);
        _mintAndApprove(testPool, caller, 200);
        _configureHooks(testPool, 0, actionBit);

        // Two assets per share, so 100 shares cost 200 assets.
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (
                    address(testPool),
                    Phase.AFTER,
                    ActionLib.POOL_MINT,
                    abi.encode(receiver, caller, caller, uint256(200), uint256(100))
                )
            ),
            1
        );

        vm.prank(caller);
        testPool.mint(100, receiver);
    }

    function test_mint_RevertsWhenBeforeHookRejectsMint() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_MINT;
        _configureHooks(actionBit, 0);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(caller);
        pool.mint(MINT_SHARES, receiver);
    }

    function test_mint_RevertsWhenAfterHookRejectsMint() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_MINT;
        _mintAndApprove(pool, caller, MINT_SHARES);
        _configureHooks(0, actionBit);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(caller);
        pool.mint(MINT_SHARES, receiver);
    }

    // withdraw()

    function test_withdraw_TransfersRequestedAssetsToReceiver() public {
        (BorrowableHarness testPool,) = _deployExitPosition(caller);

        vm.prank(caller);
        testPool.withdraw(WITHDRAW_ASSETS, receiver, caller);

        assertEq(asset.balanceOf(receiver), WITHDRAW_ASSETS);
        assertEq(asset.balanceOf(address(testPool)), EXIT_POSITION_ASSETS - WITHDRAW_ASSETS);
    }

    function test_withdraw_ReleasesAssetsFromIdleLiquidity() public {
        (BorrowableHarness testPool,) = _deployExitPosition(caller);

        vm.prank(caller);
        testPool.withdraw(WITHDRAW_ASSETS, receiver, caller);

        assertEq(testPool.idleLiquidity(), EXIT_POSITION_ASSETS - WITHDRAW_ASSETS);
    }

    function test_withdraw_BurnsCalculatedSharesFromOwner() public {
        (BorrowableHarness testPool,) = _deployExitPosition(caller);

        vm.prank(caller);
        testPool.withdraw(WITHDRAW_ASSETS, receiver, caller);

        assertEq(testPool.balanceOf(caller), EXIT_POSITION_SHARES - WITHDRAW_ASSETS);
        assertEq(testPool.totalSupply(), EXIT_POSITION_SHARES - WITHDRAW_ASSETS);
    }

    function test_withdraw_ReturnsTheAmountOfSharesBurned() public {
        (BorrowableHarness testPool,) = _deployExitPosition(caller);

        vm.prank(caller);
        uint256 shares = testPool.withdraw(WITHDRAW_ASSETS, receiver, caller);

        assertEq(shares, WITHDRAW_ASSETS);
    }

    function test_withdraw_ExecutesHooksAndInterestAccountingInOrder() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployExitPosition(caller);
        uint256 actionBit = uint256(1) << ActionLib.POOL_WITHDRAW;
        _configureHooks(testPool, actionBit, actionBit);

        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(
            address(testPool),
            Phase.BEFORE,
            ActionLib.POOL_WITHDRAW,
            abi.encode(caller, receiver, caller, WITHDRAW_ASSETS)
        );
        vm.expectEmit(address(testDebtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(testPool));
        emit IERC4626.Withdraw(caller, receiver, caller, WITHDRAW_ASSETS, WITHDRAW_ASSETS);
        vm.expectEmit(address(testDebtToken));
        emit MockDebtToken.UpdateBorrowRatesCalled(EXIT_POSITION_ASSETS - WITHDRAW_ASSETS);
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(
            address(testPool),
            Phase.AFTER,
            ActionLib.POOL_WITHDRAW,
            abi.encode(caller, receiver, caller, WITHDRAW_ASSETS, WITHDRAW_ASSETS)
        );

        vm.prank(caller);
        testPool.withdraw(WITHDRAW_ASSETS, receiver, caller);
    }

    function test_withdraw_PricesSharesUsingOutstandingDebt() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);

        vm.prank(caller);
        uint256 shares = testPool.withdraw(200, receiver, caller);

        // 1,000,000 shares against 3,000,000 assets, each side lifted by the virtual pair, prices the
        // pool at exactly 4,000,000 / 2,000,000 = two assets per share.
        assertEq(shares, 100);
    }

    function test_withdraw_RevertsWhenAssetsAreZero() public {
        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(caller);
        pool.withdraw(0, receiver, caller);
    }

    function test_withdraw_AllowsAssetsAtAvailableLiquidityLimit() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        _seedIdleLiquidity(testPool, 400);
        testDebtToken.seedDebt(borrower, 600);

        vm.prank(caller);
        testPool.withdraw(400, receiver, caller);

        assertEq(asset.balanceOf(receiver), 400);
    }

    function test_withdraw_RevertsWhenAssetsExceedAvailableLiquidity() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        _seedIdleLiquidity(testPool, 400);
        testDebtToken.seedDebt(borrower, 600);

        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, caller, uint256(401), uint256(400))
        );
        vm.prank(caller);
        testPool.withdraw(401, receiver, caller);
    }

    function test_withdraw_RecomputesBorrowRatesOnUpdatedIdleLiquidity() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        _seedIdleLiquidity(testPool, 1500);
        testDebtToken.seedDebt(borrower, 500);

        // The 1,500 idle less the 1,000 withdrawn.
        vm.expectCall(address(testDebtToken), abi.encodeCall(IDebtToken.updateBorrowRates, (500)), 1);
        vm.prank(caller);
        testPool.withdraw(1000, receiver, caller);
    }

    function test_withdraw_FiresBeforeHookWithWithdrawData() public {
        (BorrowableHarness testPool,) = _deployExitPosition(other);
        uint256 actionBit = uint256(1) << ActionLib.POOL_WITHDRAW;
        vm.prank(other);
        testPool.approve(operator, WITHDRAW_ASSETS);
        _configureHooks(testPool, actionBit, 0);

        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (
                    address(testPool),
                    Phase.BEFORE,
                    ActionLib.POOL_WITHDRAW,
                    abi.encode(other, receiver, operator, WITHDRAW_ASSETS)
                )
            ),
            1
        );

        vm.prank(operator);
        testPool.withdraw(WITHDRAW_ASSETS, receiver, other);
    }

    function test_withdraw_FiresAfterHookWithWithdrawResult() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        uint256 actionBit = uint256(1) << ActionLib.POOL_WITHDRAW;
        testPool.seedShares(other, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);
        vm.prank(other);
        testPool.approve(operator, 100);
        _configureHooks(testPool, 0, actionBit);

        // Two assets per share, so withdrawing 200 assets burns 100 shares.
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (
                    address(testPool),
                    Phase.AFTER,
                    ActionLib.POOL_WITHDRAW,
                    abi.encode(other, receiver, operator, uint256(200), uint256(100))
                )
            ),
            1
        );

        vm.prank(operator);
        testPool.withdraw(200, receiver, other);
    }

    function test_withdraw_RevertsWhenBeforeHookRejectsWithdraw() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_WITHDRAW;
        _configureHooks(actionBit, 0);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(operator);
        pool.withdraw(WITHDRAW_ASSETS, receiver, other);
    }

    function test_withdraw_RevertsWhenAfterHookRejectsWithdraw() public {
        (BorrowableHarness testPool,) = _deployExitPosition(other);
        uint256 actionBit = uint256(1) << ActionLib.POOL_WITHDRAW;
        vm.prank(other);
        testPool.approve(operator, WITHDRAW_ASSETS);
        _configureHooks(testPool, 0, actionBit);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(operator);
        testPool.withdraw(WITHDRAW_ASSETS, receiver, other);
    }

    // redeem()

    function test_redeem_TransfersCalculatedAssetsToReceiver() public {
        (BorrowableHarness testPool,) = _deployExitPosition(caller);

        vm.prank(caller);
        testPool.redeem(REDEEM_SHARES, receiver, caller);

        assertEq(asset.balanceOf(receiver), REDEEM_SHARES);
        assertEq(asset.balanceOf(address(testPool)), EXIT_POSITION_ASSETS - REDEEM_SHARES);
    }

    function test_redeem_ReleasesAssetsFromIdleLiquidity() public {
        (BorrowableHarness testPool,) = _deployExitPosition(caller);

        vm.prank(caller);
        testPool.redeem(REDEEM_SHARES, receiver, caller);

        assertEq(testPool.idleLiquidity(), EXIT_POSITION_ASSETS - REDEEM_SHARES);
    }

    function test_redeem_BurnsRequestedSharesFromOwner() public {
        (BorrowableHarness testPool,) = _deployExitPosition(caller);

        vm.prank(caller);
        testPool.redeem(REDEEM_SHARES, receiver, caller);

        assertEq(testPool.balanceOf(caller), EXIT_POSITION_SHARES - REDEEM_SHARES);
        assertEq(testPool.totalSupply(), EXIT_POSITION_SHARES - REDEEM_SHARES);
    }

    function test_redeem_ReturnsTheAmountOfAssetsReceived() public {
        (BorrowableHarness testPool,) = _deployExitPosition(caller);

        vm.prank(caller);
        uint256 assets = testPool.redeem(REDEEM_SHARES, receiver, caller);

        assertEq(assets, REDEEM_SHARES);
    }

    function test_redeem_ExecutesHooksAndInterestAccountingInOrder() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployExitPosition(caller);
        uint256 actionBit = uint256(1) << ActionLib.POOL_REDEEM;
        _configureHooks(testPool, actionBit, actionBit);

        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(
            address(testPool), Phase.BEFORE, ActionLib.POOL_REDEEM, abi.encode(caller, receiver, caller, REDEEM_SHARES)
        );
        vm.expectEmit(address(testDebtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(testPool));
        emit IERC4626.Withdraw(caller, receiver, caller, REDEEM_SHARES, REDEEM_SHARES);
        vm.expectEmit(address(testDebtToken));
        emit MockDebtToken.UpdateBorrowRatesCalled(EXIT_POSITION_ASSETS - REDEEM_SHARES);
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(
            address(testPool),
            Phase.AFTER,
            ActionLib.POOL_REDEEM,
            abi.encode(caller, receiver, caller, REDEEM_SHARES, REDEEM_SHARES)
        );

        vm.prank(caller);
        testPool.redeem(REDEEM_SHARES, receiver, caller);
    }

    function test_redeem_PricesAssetsUsingOutstandingDebt() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);

        vm.prank(caller);
        uint256 assets = testPool.redeem(100, receiver, caller);

        // 1,000,000 shares against 3,000,000 assets, each side lifted by the virtual pair, prices the
        // pool at exactly 4,000,000 / 2,000,000 = two assets per share.
        assertEq(assets, 200);
    }

    function test_redeem_RevertsWhenSharesAreZero() public {
        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(caller);
        pool.redeem(0, receiver, caller);
    }

    function test_redeem_RevertsWhenPositiveSharesWouldReturnZeroAssets() public {
        (BorrowableHarness testPool,) = _deployBorrowableHarness();
        testPool.seedShares(caller, 3);
        _seedIdleLiquidity(testPool, 1);

        // floor(1 share * 1,000,001 adjusted assets / 1,000,003 adjusted shares) = 0 assets.
        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(caller);
        testPool.redeem(1, receiver, caller);
    }

    function test_redeem_AllowsSharesAtAvailableLiquidityLimit() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        _seedIdleLiquidity(testPool, 400);
        testDebtToken.seedDebt(borrower, 600);

        vm.prank(caller);
        testPool.redeem(400, receiver, caller);

        assertEq(asset.balanceOf(receiver), 400);
    }

    function test_redeem_RevertsWhenSharesExceedAvailableLiquidity() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        _seedIdleLiquidity(testPool, 400);
        testDebtToken.seedDebt(borrower, 600);

        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxRedeem.selector, caller, uint256(401), uint256(400))
        );
        vm.prank(caller);
        testPool.redeem(401, receiver, caller);
    }

    function test_redeem_RecomputesBorrowRatesOnUpdatedIdleLiquidity() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 2000);
        _seedIdleLiquidity(testPool, 1500);
        testDebtToken.seedDebt(borrower, 500);

        // 2,000 assets back 2,000 shares, so the 1,500 idle less the 1,000 the redemption pays out.
        vm.expectCall(address(testDebtToken), abi.encodeCall(IDebtToken.updateBorrowRates, (500)), 1);
        vm.prank(caller);
        testPool.redeem(1000, receiver, caller);
    }

    function test_redeem_FiresBeforeHookWithRedeemData() public {
        (BorrowableHarness testPool,) = _deployExitPosition(other);
        uint256 actionBit = uint256(1) << ActionLib.POOL_REDEEM;
        vm.prank(other);
        testPool.approve(operator, REDEEM_SHARES);
        _configureHooks(testPool, actionBit, 0);

        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (
                    address(testPool),
                    Phase.BEFORE,
                    ActionLib.POOL_REDEEM,
                    abi.encode(other, receiver, operator, REDEEM_SHARES)
                )
            ),
            1
        );

        vm.prank(operator);
        testPool.redeem(REDEEM_SHARES, receiver, other);
    }

    function test_redeem_FiresAfterHookWithRedeemResult() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        uint256 actionBit = uint256(1) << ActionLib.POOL_REDEEM;
        testPool.seedShares(other, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);
        vm.prank(other);
        testPool.approve(operator, 100);
        _configureHooks(testPool, 0, actionBit);

        // Two assets per share, so redeeming 100 shares pays out 200 assets.
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (
                    address(testPool),
                    Phase.AFTER,
                    ActionLib.POOL_REDEEM,
                    abi.encode(other, receiver, operator, uint256(200), uint256(100))
                )
            ),
            1
        );

        vm.prank(operator);
        testPool.redeem(100, receiver, other);
    }

    function test_redeem_RevertsWhenBeforeHookRejectsRedeem() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_REDEEM;
        _configureHooks(actionBit, 0);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(operator);
        pool.redeem(REDEEM_SHARES, receiver, other);
    }

    function test_redeem_RevertsWhenAfterHookRejectsRedeem() public {
        (BorrowableHarness testPool,) = _deployExitPosition(other);
        uint256 actionBit = uint256(1) << ActionLib.POOL_REDEEM;
        vm.prank(other);
        testPool.approve(operator, REDEEM_SHARES);
        _configureHooks(testPool, 0, actionBit);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(operator);
        testPool.redeem(REDEEM_SHARES, receiver, other);
    }

    // transfer()

    function test_transfer_ReturnsTrue() public {
        BorrowableHarness testPool = _deployTransferPosition();

        vm.prank(caller);
        bool ok = testPool.transfer(receiver, TRANSFER_SHARES);

        assertTrue(ok);
    }

    function test_transfer_ExecutesHooksAroundShareTransferInOrder() public {
        BorrowableHarness testPool = _deployTransferPosition();
        uint256 actionBit = uint256(1) << ActionLib.POOL_TRANSFER;
        _configureHooks(testPool, actionBit, actionBit);
        bytes memory data = abi.encode(caller, receiver, caller, TRANSFER_SHARES);

        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(address(testPool), Phase.BEFORE, ActionLib.POOL_TRANSFER, data);
        vm.expectEmit(address(testPool));
        emit IERC20.Transfer(caller, receiver, TRANSFER_SHARES);
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(address(testPool), Phase.AFTER, ActionLib.POOL_TRANSFER, data);

        vm.prank(caller);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        testPool.transfer(receiver, TRANSFER_SHARES);

        assertEq(hookReceiver.calls(), 2);
    }

    function test_transfer_RevertsWhenBeforeHookRejectsTransfer() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_TRANSFER;
        _configureHooks(actionBit, 0);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(caller);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        pool.transfer(receiver, TRANSFER_SHARES);
    }

    function test_transfer_RevertsWhenAfterHookRejectsTransfer() public {
        BorrowableHarness testPool = _deployTransferPosition();
        uint256 actionBit = uint256(1) << ActionLib.POOL_TRANSFER;
        _configureHooks(testPool, 0, actionBit);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(caller);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        testPool.transfer(receiver, TRANSFER_SHARES);
    }

    // transferFrom()

    function test_transferFrom_ReturnsTrue() public {
        BorrowableHarness testPool = _deployTransferPosition();
        vm.prank(caller);
        testPool.approve(operator, TRANSFER_SHARES);

        vm.prank(operator);
        bool ok = testPool.transferFrom(caller, receiver, TRANSFER_SHARES);

        assertTrue(ok);
    }

    function test_transferFrom_ExecutesHooksAroundShareTransferInOrder() public {
        BorrowableHarness testPool = _deployTransferPosition();
        vm.prank(caller);
        testPool.approve(operator, TRANSFER_SHARES);
        uint256 actionBit = uint256(1) << ActionLib.POOL_TRANSFER;
        _configureHooks(testPool, actionBit, actionBit);
        bytes memory data = abi.encode(caller, receiver, operator, TRANSFER_SHARES);

        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(address(testPool), Phase.BEFORE, ActionLib.POOL_TRANSFER, data);
        vm.expectEmit(address(testPool));
        emit IERC20.Transfer(caller, receiver, TRANSFER_SHARES);
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(address(testPool), Phase.AFTER, ActionLib.POOL_TRANSFER, data);

        vm.prank(operator);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        testPool.transferFrom(caller, receiver, TRANSFER_SHARES);

        assertEq(hookReceiver.calls(), 2);
    }

    function test_transferFrom_RevertsWhenBeforeHookRejectsTransfer() public {
        uint256 actionBit = uint256(1) << ActionLib.POOL_TRANSFER;
        _configureHooks(actionBit, 0);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(operator);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        pool.transferFrom(caller, receiver, TRANSFER_SHARES);
    }

    function test_transferFrom_RevertsWhenAfterHookRejectsTransfer() public {
        BorrowableHarness testPool = _deployTransferPosition();
        vm.prank(caller);
        testPool.approve(operator, TRANSFER_SHARES);
        uint256 actionBit = uint256(1) << ActionLib.POOL_TRANSFER;
        _configureHooks(testPool, 0, actionBit);
        hookReceiver.setShouldRevert(true);

        vm.expectRevert(MockHookReceiver.HookReceiverReverted.selector);
        vm.prank(operator);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        testPool.transferFrom(caller, receiver, TRANSFER_SHARES);
    }

    // totalAssets()

    function test_totalAssets_ReturnsZeroWhenPoolIsEmpty() public view {
        assertEq(pool.totalAssets(), 0);
    }

    function test_totalAssets_ReturnsIdleLiquidityWhenThereIsNoDebt() public {
        _seedIdleLiquidity(pool, IDLE_LIQUIDITY);

        assertEq(pool.totalAssets(), 1000e18);
    }

    function test_totalAssets_ReturnsDebtWhenThereIsNoIdleLiquidity() public {
        debtToken.seedDebt(caller, TOTAL_DEBT);

        assertEq(pool.totalAssets(), 500e18);
    }

    function test_totalAssets_AddsIdleLiquidityAndDebt() public {
        _seedIdleLiquidity(pool, IDLE_LIQUIDITY);
        debtToken.seedDebt(caller, TOTAL_DEBT);

        assertEq(pool.totalAssets(), 1500e18);
    }

    // totalDebt()

    function test_totalDebt_ReturnsOutstandingDebt() public {
        debtToken.seedDebt(caller, TOTAL_DEBT);

        assertEq(pool.totalDebt(), 500e18);
    }

    // debtOf()

    function test_debtOf_ReadsEachAccountsDebtFromDebtToken() public {
        debtToken.seedDebt(caller, 500e18);
        debtToken.seedDebt(other, 100e18);

        assertEq(pool.debtOf(caller), 500e18);
        assertEq(pool.debtOf(other), 100e18);
    }

    // totalSupply()

    function test_totalSupply_ReturnsZeroWhenPoolIsEmpty() public view {
        assertEq(pool.totalSupply(), 0);
    }

    function test_totalSupply_AddsHeldSharesAndFeeShares() public {
        (BorrowableHarness testPool,) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);

        testPool.seedOperatorFeeShares(60);
        testPool.seedOnlendFeeShares(40);

        assertEq(testPool.totalSupply(), 1100);
    }

    /// @dev `totalAssets` already carries the interest the pending fees are taken from, so the shares claiming them
    ///      must be counted before they are handed over — otherwise every conversion prices the operator's and Onlend's
    ///      share of that interest as if it belonged to depositors.
    function test_totalSupply_AddsSharesOwedOnPendingInterest() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        // 1,000 of the assets back the shares already held; the remaining 30 is fees on interest not yet handed over,
        // so they buy shares one for one.
        _seedIdleLiquidity(testPool, 1030);

        // Of 100 accrued with 20 retained, the operator and Onlend are each owed 15.
        testDebtToken.setNextInterest(100, 20);

        assertEq(testPool.totalSupply(), 1030);
    }

    // maxDeposit()

    function test_maxDeposit_ReturnsAssetsWhoseSharesReachMaxDepositShares() public {
        (BorrowableHarness testPool,) = _deployBorrowableHarness();
        testPool.seedShares(other, 1e6);
        _seedIdleLiquidity(testPool, 3e6);

        uint256 maxAssets = testPool.maxDeposit(receiver);

        // 1,000,000 shares against 3,000,000 assets price at two assets per share, so the shares left under the
        // cap cost twice as many assets.
        assertEq(maxAssets, 2 * (ShareMath.MAX_DEPOSIT_SHARES - 1e6));
    }

    function test_maxDeposit_ReturnsZeroWhenTotalSupplyIsAtMaxDepositShares() public {
        (BorrowableHarness testPool,) = _deployBorrowableHarness();
        testPool.seedShares(other, ShareMath.MAX_DEPOSIT_SHARES);

        uint256 maxAssets = testPool.maxDeposit(receiver);

        assertEq(maxAssets, 0);
    }

    // maxMint()

    function test_maxMint_ReturnsSharesLeftUnderMaxDepositShares() public {
        BorrowableHarness testPool = _deployMaxDepositRoomPosition();

        uint256 maxShares = testPool.maxMint(receiver);

        assertEq(maxShares, MAX_DEPOSIT_ROOM);
    }

    function test_maxMint_ReturnsZeroWhenTotalSupplyIsAtMaxDepositShares() public {
        (BorrowableHarness testPool,) = _deployBorrowableHarness();
        testPool.seedShares(other, ShareMath.MAX_DEPOSIT_SHARES);

        uint256 maxShares = testPool.maxMint(receiver);

        assertEq(maxShares, 0);
    }

    function test_maxMint_ReturnsZeroWhenFeeSharesTakeTotalSupplyPastMaxDepositShares() public {
        (BorrowableHarness testPool,) = _deployBorrowableHarness();
        testPool.seedShares(other, ShareMath.MAX_DEPOSIT_SHARES);
        testPool.seedOperatorFeeShares(1);

        uint256 maxShares = testPool.maxMint(receiver);

        assertEq(maxShares, 0);
    }

    // maxRedeem()

    function test_maxRedeem_ReturnsZeroWhenOwnerHasNoShares() public {
        (BorrowableHarness testPool,) = _deployBorrowableHarness();
        testPool.seedShares(other, 1000);
        _seedIdleLiquidity(testPool, 1000);

        uint256 maxShares = testPool.maxRedeem(caller);

        assertEq(maxShares, 0);
    }

    function test_maxRedeem_ReturnsZeroWhenAllLiquidityIsBorrowed() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        testDebtToken.seedDebt(borrower, 1000);

        uint256 maxShares = testPool.maxRedeem(caller);

        assertEq(maxShares, 0);
    }

    function test_maxRedeem_ReturnsZeroWhenPositiveIdleLiquidityRoundsDownToZeroShares() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 2);
        _seedIdleLiquidity(testPool, 1);
        testDebtToken.seedDebt(borrower, 3);

        uint256 maxShares = testPool.maxRedeem(caller);

        // One idle asset converts to floor(1 * 1,000,002 adjusted shares / 1,000,004 adjusted assets) = 0 shares.
        assertEq(maxShares, 0);
    }

    function test_maxRedeem_ReturnsOwnerSharesWhenBelowIdleShareCapacity() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 200);
        testPool.seedShares(other, 800);
        _seedIdleLiquidity(testPool, 1000);
        testDebtToken.seedDebt(borrower, 500);

        uint256 maxShares = testPool.maxRedeem(caller);

        assertEq(maxShares, 200);
    }

    function test_maxRedeem_ReturnsOwnerSharesWhenEqualToIdleShareCapacity() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 500);
        testPool.seedShares(other, 500);
        _seedIdleLiquidity(testPool, 500);
        testDebtToken.seedDebt(borrower, 500);

        uint256 maxShares = testPool.maxRedeem(caller);

        assertEq(maxShares, 500);
    }

    function test_maxRedeem_ReturnsIdleShareCapacityWhenBelowOwnerShares() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1e6);
        _seedIdleLiquidity(testPool, 1e6);
        testDebtToken.seedDebt(borrower, 2e6);

        uint256 maxShares = testPool.maxRedeem(caller);

        // 1,000,000 shares against 3,000,000 assets price at two assets per share, so the 1,000,000 idle assets
        // convert to 500,000 shares — less than the 1,000,000 the owner holds.
        assertEq(maxShares, 500_000);
    }

    // supportsInterface()

    function test_supportsInterface_ReturnsTrueForBorrowable() public view {
        assertTrue(pool.supportsInterface(type(IBorrowable).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForPool() public view {
        assertTrue(pool.supportsInterface(type(IPool).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForERC3156FlashLender() public view {
        assertTrue(pool.supportsInterface(type(IERC3156FlashLender).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForVersioned() public view {
        assertTrue(pool.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForERC165() public view {
        assertTrue(pool.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForAccessControl() public view {
        assertTrue(pool.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForAccessControlEnumerable() public view {
        assertTrue(pool.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_ReturnsFalseForUnknownInterface() public view {
        assertFalse(pool.supportsInterface(bytes4(0xffffffff)));
    }

    // _borrow()

    function test_borrow_RevertsWhenAmountIsZero() public {
        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(lendingCore);
        pool.borrow(caller, 0, receiver);
    }

    function test_borrow_AllowsAmountAtIdleLiquidityLimit() public {
        _seedIdleLiquidity(pool, BORROW_LIQUIDITY);

        vm.prank(lendingCore);
        pool.borrow(caller, BORROW_LIQUIDITY, receiver);

        assertEq(asset.balanceOf(receiver), BORROW_LIQUIDITY);
        assertEq(pool.idleLiquidity(), 0);
    }

    /// @dev The donated underlying leaves the pool holding more than it lends against, so a borrow that only fits
    ///      inside the donation is refused: the pool lends what it has accounted for, not what it happens to hold.
    function test_borrow_RevertsWhenAmountExceedsIdleLiquidityDespiteDonatedBalance() public {
        _seedIdleLiquidity(pool, BORROW_LIQUIDITY);
        asset.mint(address(pool), BORROW_LIQUIDITY);

        vm.expectRevert(
            abi.encodeWithSelector(
                Borrowable.InsufficientIdleLiquidity.selector, BORROW_LIQUIDITY + 1, BORROW_LIQUIDITY
            )
        );
        vm.prank(lendingCore);
        pool.borrow(caller, BORROW_LIQUIDITY + 1, receiver);
    }

    function test_borrow_TransfersBorrowedAssetsToReceiver() public {
        _seedIdleLiquidity(pool, BORROW_LIQUIDITY);

        vm.prank(lendingCore);
        pool.borrow(caller, BORROW_AMOUNT, receiver);

        assertEq(asset.balanceOf(receiver), BORROW_AMOUNT);
        assertEq(asset.balanceOf(address(pool)), BORROW_LIQUIDITY - BORROW_AMOUNT);
    }

    function test_borrow_ReleasesBorrowedAssetsFromIdleLiquidity() public {
        _seedIdleLiquidity(pool, BORROW_LIQUIDITY);

        vm.prank(lendingCore);
        pool.borrow(caller, BORROW_AMOUNT, receiver);

        assertEq(pool.idleLiquidity(), BORROW_LIQUIDITY - BORROW_AMOUNT);
    }

    function test_borrow_MintsDebtForCaller() public {
        _seedIdleLiquidity(pool, BORROW_LIQUIDITY);

        vm.expectCall(address(debtToken), abi.encodeCall(IDebtToken.mint, (caller, BORROW_AMOUNT)), 1);

        vm.prank(lendingCore);
        pool.borrow(caller, BORROW_AMOUNT, receiver);
    }

    function test_borrow_ExecutesDebtAccountingTransferAndRateUpdateInOrder() public {
        _seedIdleLiquidity(pool, BORROW_LIQUIDITY);

        vm.expectEmit(address(debtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.MintCalled(caller, BORROW_AMOUNT);
        vm.expectEmit(address(asset));
        emit IERC20.Transfer(address(pool), receiver, BORROW_AMOUNT);
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.UpdateBorrowRatesCalled(BORROW_LIQUIDITY - BORROW_AMOUNT);

        vm.prank(lendingCore);
        pool.borrow(caller, BORROW_AMOUNT, receiver);
    }

    // _repay()

    function test_repay_RevertsWhenAmountIsZero() public {
        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(lendingCore);
        pool.repay(caller, 0, receiver);
    }

    function test_repay_RevertsWhenReceiverHasNoDebt() public {
        debtToken.seedDebt(caller, REPAY_DEBT);

        vm.expectRevert(abi.encodeWithSelector(Borrowable.NoDebt.selector, receiver));
        vm.prank(lendingCore);
        pool.repay(caller, REPAY_AMOUNT, receiver);
    }

    function test_repay_TransfersRequestedAmountWhenBelowDebt() public {
        debtToken.seedDebt(receiver, REPAY_DEBT);
        _mintAndApprove(pool, caller, REPAY_AMOUNT);

        vm.prank(lendingCore);
        pool.repay(caller, REPAY_AMOUNT, receiver);

        assertEq(asset.balanceOf(caller), 0);
        assertEq(asset.balanceOf(address(pool)), REPAY_AMOUNT);
    }

    function test_repay_BooksRepaymentAsIdleLiquidity() public {
        debtToken.seedDebt(receiver, REPAY_DEBT);
        _mintAndApprove(pool, caller, REPAY_AMOUNT);

        vm.prank(lendingCore);
        pool.repay(caller, REPAY_AMOUNT, receiver);

        assertEq(pool.idleLiquidity(), REPAY_AMOUNT);
    }

    function test_repay_ReturnsRequestedAmountWhenBelowDebt() public {
        debtToken.seedDebt(receiver, REPAY_DEBT);
        _mintAndApprove(pool, caller, REPAY_AMOUNT);

        vm.prank(lendingCore);
        uint256 repayment = pool.repay(caller, REPAY_AMOUNT, receiver);

        assertEq(repayment, REPAY_AMOUNT);
    }

    function test_repay_RepaysFullDebtWhenAmountEqualsDebt() public {
        debtToken.seedDebt(receiver, REPAY_AMOUNT);
        _mintAndApprove(pool, caller, REPAY_AMOUNT);

        vm.expectCall(address(debtToken), abi.encodeCall(IDebtToken.burn, (receiver, REPAY_AMOUNT)), 1);

        vm.prank(lendingCore);
        pool.repay(caller, REPAY_AMOUNT, receiver);

        assertEq(asset.balanceOf(caller), 0);
        assertEq(asset.balanceOf(address(pool)), REPAY_AMOUNT);
    }

    function test_repay_CapsRepaymentToDebtWhenAmountExceedsDebt() public {
        debtToken.seedDebt(receiver, REPAY_AMOUNT);
        _mintAndApprove(pool, caller, REPAY_DEBT);

        vm.expectCall(address(debtToken), abi.encodeCall(IDebtToken.burn, (receiver, REPAY_AMOUNT)), 1);

        vm.prank(lendingCore);
        pool.repay(caller, REPAY_DEBT, receiver);

        assertEq(asset.balanceOf(caller), REPAY_DEBT - REPAY_AMOUNT);
        assertEq(asset.balanceOf(address(pool)), REPAY_AMOUNT);
    }

    function test_repay_ReturnsDebtWhenAmountExceedsDebt() public {
        debtToken.seedDebt(receiver, REPAY_AMOUNT);
        _mintAndApprove(pool, caller, REPAY_DEBT);

        vm.prank(lendingCore);
        uint256 repayment = pool.repay(caller, REPAY_DEBT, receiver);

        assertEq(repayment, REPAY_AMOUNT);
    }

    function test_repay_ExecutesDebtAccountingTransferAndRateUpdateInOrder() public {
        _seedIdleLiquidity(pool, REPAY_IDLE_LIQUIDITY);
        debtToken.seedDebt(receiver, REPAY_DEBT);
        _mintAndApprove(pool, caller, REPAY_AMOUNT);

        vm.expectEmit(address(debtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(asset));
        emit IERC20.Transfer(caller, address(pool), REPAY_AMOUNT);
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.BurnCalled(receiver, REPAY_AMOUNT);
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.UpdateBorrowRatesCalled(REPAY_IDLE_LIQUIDITY + REPAY_AMOUNT);

        vm.prank(lendingCore);
        pool.repay(caller, REPAY_AMOUNT, receiver);
    }

    // _writeOffDebt()

    function test_writeOffDebt_RevertsWhenAccountHasNoDebt() public {
        debtToken.seedDebt(other, WRITE_OFF_DEBT);

        vm.expectRevert(abi.encodeWithSelector(Borrowable.NoDebt.selector, borrower));
        vm.prank(lendingCore);
        pool.writeOffDebt(borrower);
    }

    function test_writeOffDebt_BurnsWholeDebt() public {
        debtToken.seedDebt(borrower, WRITE_OFF_DEBT);

        vm.expectCall(address(debtToken), abi.encodeCall(IDebtToken.burn, (borrower, WRITE_OFF_DEBT)), 1);

        vm.prank(lendingCore);
        pool.writeOffDebt(borrower);

        assertEq(pool.debtOf(borrower), 0);
    }

    function test_writeOffDebt_ReturnsWrittenOffDebt() public {
        debtToken.seedDebt(borrower, WRITE_OFF_DEBT);

        vm.prank(lendingCore);
        uint256 writtenOff = pool.writeOffDebt(borrower);

        assertEq(writtenOff, WRITE_OFF_DEBT);
    }

    function test_writeOffDebt_LeavesIdleLiquidityAndBalanceUnchanged() public {
        _seedIdleLiquidity(pool, WRITE_OFF_IDLE_LIQUIDITY);
        debtToken.seedDebt(borrower, WRITE_OFF_DEBT);

        vm.prank(lendingCore);
        pool.writeOffDebt(borrower);

        assertEq(pool.idleLiquidity(), WRITE_OFF_IDLE_LIQUIDITY);
        assertEq(asset.balanceOf(address(pool)), WRITE_OFF_IDLE_LIQUIDITY);
    }

    function test_writeOffDebt_ReducesTotalAssetsByWrittenOffDebt() public {
        _seedIdleLiquidity(pool, WRITE_OFF_IDLE_LIQUIDITY);
        debtToken.seedDebt(borrower, WRITE_OFF_DEBT);

        vm.prank(lendingCore);
        pool.writeOffDebt(borrower);

        assertEq(pool.totalAssets(), WRITE_OFF_IDLE_LIQUIDITY);
    }

    function test_writeOffDebt_LowersSharePrice() public {
        pool.seedShares(other, WRITE_OFF_DEPOSITOR_SHARES);
        _seedIdleLiquidity(pool, WRITE_OFF_IDLE_LIQUIDITY);
        debtToken.seedDebt(borrower, WRITE_OFF_DEBT);
        // 3,000,000 shares against 3,000,000 assets, each side lifted by the virtual pair, price at
        // 4,000,000 / 4,000,000 = one asset per share.
        assertEq(pool.convertToAssets(WRITE_OFF_DEPOSITOR_SHARES), 3_000_000);

        vm.prank(lendingCore);
        pool.writeOffDebt(borrower);

        // Only the 1,000,000 idle remains, so the price falls to 2,000,000 / 4,000,000 = half an asset per share.
        assertEq(pool.convertToAssets(WRITE_OFF_DEPOSITOR_SHARES), 1_500_000);
    }

    function test_writeOffDebt_EmitsDebtWrittenOff() public {
        debtToken.seedDebt(borrower, WRITE_OFF_DEBT);

        vm.expectEmit(address(pool));
        emit Borrowable.DebtWrittenOff(borrower, WRITE_OFF_DEBT);

        vm.prank(lendingCore);
        pool.writeOffDebt(borrower);
    }

    function test_writeOffDebt_ExecutesDebtAccountingAndRateUpdateInOrder() public {
        _seedIdleLiquidity(pool, WRITE_OFF_IDLE_LIQUIDITY);
        debtToken.seedDebt(borrower, WRITE_OFF_DEBT);

        vm.expectEmit(address(debtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.BurnCalled(borrower, WRITE_OFF_DEBT);
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.UpdateBorrowRatesCalled(WRITE_OFF_IDLE_LIQUIDITY);

        vm.prank(lendingCore);
        pool.writeOffDebt(borrower);
    }

    // _accrueInterest()

    function test_accrueInterest_AccruesDebtTokenInterestWithoutUpdatingRates() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();

        vm.expectCall(address(testDebtToken), abi.encodeCall(IDebtToken.accrueInterest, ()), 1);
        vm.expectCall(address(testDebtToken), abi.encodeCall(IDebtToken.updateBorrowRates, (0)), 0);

        vm.prank(caller);
        testPool.exposedAccrueInterest();
    }

    /// @dev The fee shares must be worth the fees, and the depositors' shares must still be worth what they were
    ///      before the accrual — the fees are the whole of what they give up.
    function test_accrueInterest_ConvertsFeesToShares() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        // Of 100 accrued with 20 retained, the operator and Onlend each take 15, on top of the 1000 already backing
        // those shares.
        _seedIdleLiquidity(testPool, 1030);
        testDebtToken.setNextInterest(100, 20);

        vm.prank(caller);
        testPool.exposedAccrueInterest();

        // 1030 assets now back 1030 shares, so each side is worth exactly what it holds.
        assertEq(testPool.totalOperatorFeeShares(), 15);
        assertEq(testPool.totalOnlendFeeShares(), 15);
        assertEq(testPool.convertToAssets(15), 15);
        assertEq(testPool.convertToAssets(1000), 1000);
    }

    /// @dev Interest already accruing is charged at the fee configuration in force when it started, so a registry
    ///      change only applies once the pool next updates its rates.
    function test_accrueInterest_AppliesFeeConfigCachedAtLastRateUpdate() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        _seedIdleLiquidity(testPool, 1020);
        testDebtToken.setNextInterest(100, 20);
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);

        vm.prank(caller);
        testPool.exposedAccrueInterest();

        // The pool still holds the zero fees it read at deployment, so the operator keeps all 20 retained.
        assertEq(testPool.totalOperatorFeeShares(), 20);
        assertEq(testPool.totalOnlendFeeShares(), 0);
    }

    /// @dev Fees buy shares at the price the pool is already at, so a partial share is dropped rather than rounded
    ///      up, leaving the remainder with depositors.
    function test_accrueInterest_RoundsFeeSharesDown() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1e6);
        _seedIdleLiquidity(testPool, 3_000_005);
        testDebtToken.setNextInterest(5, 5);

        vm.prank(caller);
        testPool.exposedAccrueInterest();

        // 5 of fees against the 3,000,000 backing the existing 1,000,000 shares buys
        // 5 * 2,000,000 / 4,000,000 = 2.5 shares.
        assertEq(testPool.totalOperatorFeeShares(), 2);
    }

    function test_accrueInterest_BooksNoSharesWhenFeeIsBelowOneShare() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1e6);
        _seedIdleLiquidity(testPool, 3_000_001);
        testDebtToken.setNextInterest(1, 1);

        vm.prank(caller);
        testPool.exposedAccrueInterest();

        // 1 * 2,000,000 / 4,000,000 = 0.5 shares, so nothing is booked and the whole amount stays with depositors.
        assertEq(testPool.totalOperatorFeeShares(), 0);
    }

    function test_accrueInterest_BooksNoSharesWhenNoFeesAreTaken() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1000);
        _seedIdleLiquidity(testPool, 1100);
        testDebtToken.setNextInterest(100, 0);

        vm.prank(caller);
        testPool.exposedAccrueInterest();

        assertEq(testPool.totalOperatorFeeShares(), 0);
        assertEq(testPool.totalOnlendFeeShares(), 0);
    }

    function test_accrueInterest_BooksFeeSharesReachingMaxTotalShares() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, ShareMath.MAX_TOTAL_SHARES - 50);
        _seedIdleLiquidity(testPool, ShareMath.MAX_TOTAL_SHARES);
        testDebtToken.setNextInterest(100, 40);

        vm.prank(caller);
        testPool.exposedAccrueInterest();

        // Of 100 accrued with 40 retained, the operator takes 30 and Onlend 20. The assets left after both match the
        // shares, so together they buy 50 shares at one per asset, exactly the 50 left under `MAX_TOTAL_SHARES`.
        assertEq(testPool.totalOperatorFeeShares(), 30);
        assertEq(testPool.totalOnlendFeeShares(), 20);
        assertEq(testPool.totalSupply(), ShareMath.MAX_TOTAL_SHARES);
    }

    function test_accrueInterest_WithholdsFeesWhoseCombinedSharesWouldExceedMaxTotalShares() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, ShareMath.MAX_TOTAL_SHARES - 49);
        _seedIdleLiquidity(testPool, ShareMath.MAX_TOTAL_SHARES + 1);
        testDebtToken.setNextInterest(100, 40);

        vm.expectEmit(address(testPool));
        emit Borrowable.InterestAccrued(100, 0, 0, 0, 0);

        vm.prank(caller);
        testPool.exposedAccrueInterest();

        // Of 100 accrued with 40 retained, the operator takes 30 and Onlend 20. The assets left after both match the
        // shares, so each fee alone would buy its shares at one per asset and fit in the 49 left under
        // `MAX_TOTAL_SHARES`, but together they would buy 50, one too many, so both are withheld.
        assertEq(testPool.totalOperatorFeeShares(), 0);
        assertEq(testPool.totalOnlendFeeShares(), 0);
        assertEq(testPool.totalSupply(), ShareMath.MAX_TOTAL_SHARES - 49);
    }

    function test_accrueInterest_EmitsInterestAccrued() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(caller, 1e6);
        // 3,000,000 of the assets back the 1,000,000 shares already counted, so each asset of fees buys
        // 2,000,000 / 4,000,000 = half a share.
        _seedIdleLiquidity(testPool, 3_000_050);
        testDebtToken.setNextInterest(100, 40);

        // Of 100 accrued with 40 retained, Onlend takes a 10 fixed fee and 10 of the retention, leaving 30 to the
        // operator.
        vm.expectEmit(address(testPool));
        emit Borrowable.InterestAccrued(100, 30, 20, 15, 10);

        vm.prank(caller);
        testPool.exposedAccrueInterest();
    }

    function test_accrueInterest_EmitsNothingWhenNoInterestAccrued() public {
        (BorrowableHarness testPool,) = _deployBorrowableHarness();

        vm.expectEmit(false, false, false, false, address(testPool), 0);
        emit Borrowable.InterestAccrued(0, 0, 0, 0, 0);

        vm.prank(caller);
        testPool.exposedAccrueInterest();
    }

    // _updateInterestRates()

    function test_updateInterestRates_UpdatesBorrowRatesWithIdleLiquidity() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        _seedIdleLiquidity(testPool, 1000);

        vm.expectCall(address(testDebtToken), abi.encodeCall(IDebtToken.updateBorrowRates, (1000)), 1);

        testPool.exposedUpdateInterestRates();
    }

    function test_updateInterestRates_UpdatesBorrowRatesWhenPoolIsEmpty() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();

        vm.expectCall(address(testDebtToken), abi.encodeCall(IDebtToken.updateBorrowRates, (0)), 1);

        testPool.exposedUpdateInterestRates();
    }

    function test_updateInterestRates_RefreshesOnlendFeeConfig() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);

        pool.exposedUpdateInterestRates();

        (uint16 fixedFeeBps, uint16 splitFeeBps) = pool.onlendFeeConfig();
        assertEq(fixedFeeBps, FIXED_FEE_BPS);
        assertEq(splitFeeBps, SPLIT_FEE_BPS);
    }

    function test_updateInterestRates_EmitsOnlendFeeConfigUpdatedWhenOnlyFixedFeeChanges() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, 0);

        vm.expectEmit(address(pool));
        emit Borrowable.OnlendFeeConfigUpdated(FIXED_FEE_BPS, 0);

        pool.exposedUpdateInterestRates();
    }

    function test_updateInterestRates_EmitsOnlendFeeConfigUpdatedWhenOnlySplitFeeChanges() public {
        feeRegistry.setFeeConfig(0, SPLIT_FEE_BPS);

        vm.expectEmit(address(pool));
        emit Borrowable.OnlendFeeConfigUpdated(0, SPLIT_FEE_BPS);

        pool.exposedUpdateInterestRates();
    }

    function test_updateInterestRates_EmitsNothingWhenOnlendFeeConfigIsUnchanged() public {
        feeRegistry.setFeeConfig(FIXED_FEE_BPS, SPLIT_FEE_BPS);
        pool.exposedUpdateInterestRates();

        vm.expectEmit(false, false, false, false, address(pool), 0);
        emit Borrowable.OnlendFeeConfigUpdated(0, 0);

        pool.exposedUpdateInterestRates();
    }

    function test_updateInterestRates_ReadsFeeConfigForItsOwnAddress() public {
        vm.expectCall(address(feeRegistry), abi.encodeCall(IOnlendFeeRegistry.feeConfig, (address(pool))), 1);

        pool.exposedUpdateInterestRates();
    }

    function test_updateInterestRates_EmitsPoolStateUpdated() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        _seedIdleLiquidity(testPool, 1000);
        testDebtToken.seedDebt(borrower, 2000);
        testPool.seedShares(other, 3000);
        testPool.seedOperatorFeeShares(40);
        testPool.seedOnlendFeeShares(60);

        // The reported supply counts the 100 unclaimed fee shares on top of the 3000 held.
        vm.expectEmit(address(testPool));
        emit Borrowable.PoolStateUpdated(1000, 2000, 3100);

        testPool.exposedUpdateInterestRates();
    }

    // _convertToShares()

    /// @dev Interest accrues into the asset base without issuing shares, so a share can come to cost more than a
    ///      whole deposit. The virtual amounts hold the price down to where the deposit still buys a position,
    ///      instead of rounding to nothing and leaving its assets to the existing holder.
    function test_convertToShares_DoesNotRoundAwayDepositWhenSharePriceIsHigh() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(other, 1);
        testDebtToken.seedDebt(borrower, 1e6);
        _mintAndApprove(testPool, caller, 1e6);

        vm.prank(caller);
        uint256 shares = testPool.deposit(1e6, receiver);

        // The virtual pair lifts one share against 1,000,000 assets to 1,000,001 against 2,000,000, so the deposit
        // buys floor(1,000,000 * 1,000,001 / 2,000,000) = 500,000 shares rather than none.
        assertEq(shares, 500_000);
    }

    // _convertToAssets()

    /// @dev Conversions price against the liquidity the pool has accounted for, so underlying donated to it cannot
    ///      lift the share price at all.
    function test_convertToAssets_IsUnmovedByADonation() public {
        _mintAndApprove(pool, caller, DEPOSIT_ASSETS);
        vm.prank(caller);
        uint256 shares = pool.deposit(DEPOSIT_ASSETS, caller);
        uint256 valueBefore = pool.convertToAssets(shares);

        asset.mint(address(pool), 1e6);

        assertEq(pool.convertToAssets(shares), valueBefore);
    }

    /// @dev The position those shares represent is worth what the deposit paid for it, down to the wei the floor
    ///      leaves behind, rather than a fraction of it.
    function test_convertToAssets_ValuesDepositAtWhatItPaidWhenSharePriceIsHigh() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(other, 1);
        testDebtToken.seedDebt(borrower, 1e6);
        _mintAndApprove(testPool, caller, 1e6);

        vm.prank(caller);
        uint256 shares = testPool.deposit(1e6, receiver);

        // The deposit leaves 500,001 shares against 2,000,000 assets, lifted to 1,500,001 against 3,000,000, so its
        // 500,000 shares claim floor(500,000 * 3,000,000 / 1,500,001) = 999,999 of the 1,000,000 paid.
        assertEq(testPool.previewRedeem(shares), 999_999);
    }

    /// @dev The other side of the same rounding: what the deposit keeps is what the position sitting in front of it
    ///      cannot take, so a one wei holder is worth no more after a deposit far larger than itself.
    function test_convertToAssets_DoesNotEnrichAnEarlierPositionWithALaterDeposit() public {
        (BorrowableHarness testPool, MockDebtToken testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(other, 1);
        testDebtToken.seedDebt(borrower, 1e6);
        _mintAndApprove(testPool, caller, 1e6);

        vm.prank(caller);
        testPool.deposit(1e6, receiver);

        assertEq(testPool.previewRedeem(1), 1);
    }

    // _validateDebtToken()

    function test_validateDebtToken_AcceptsTokenSupportingDebtTokenInterface() public view {
        pool.validateDebtToken(address(debtToken));
    }

    function test_validateDebtToken_RevertsWhenTokenDoesNotSupportDebtTokenInterface() public {
        address notDebtToken = makeAddr("notDebtToken");

        vm.expectRevert(abi.encodeWithSelector(Borrowable.InvalidDebtToken.selector, notDebtToken));
        pool.validateDebtToken(notDebtToken);
    }

    // flashLoan()

    function test_flashLoan_DepositWithinCallbackMintsSharesAtUnchangedPrice() public {
        _mintAndApprove(pool, other, IDLE_LIQUIDITY);
        vm.prank(other);
        pool.deposit(IDLE_LIQUIDITY, other);
        MockFlashBorrower flashBorrower = new MockFlashBorrower();
        asset.mint(address(flashBorrower), DEPOSIT_ASSETS);
        flashBorrower.addCallbackCall(address(asset), abi.encodeCall(IERC20.approve, (address(pool), DEPOSIT_ASSETS)));
        flashBorrower.addCallbackCall(
            address(pool), abi.encodeCall(IERC4626.deposit, (DEPOSIT_ASSETS, address(flashBorrower)))
        );

        pool.flashLoan(flashBorrower, address(asset), IDLE_LIQUIDITY, "");

        // The pool prices shares 1:1 outside the loan, so the deposit mints one share per unit deposited.
        assertEq(pool.balanceOf(address(flashBorrower)), DEPOSIT_ASSETS);
    }

    function test_flashLoan_RateSyncWithinCallbackPricesAgainstUnchangedIdleLiquidity() public {
        _mintAndApprove(pool, other, IDLE_LIQUIDITY);
        vm.prank(other);
        pool.deposit(IDLE_LIQUIDITY, other);
        MockFlashBorrower flashBorrower = new MockFlashBorrower();
        flashBorrower.addCallbackCall(address(pool), abi.encodeCall(Borrowable.syncInterestRate, ()));

        vm.expectCall(address(debtToken), abi.encodeCall(IDebtToken.updateBorrowRates, (IDLE_LIQUIDITY)), 1);

        pool.flashLoan(flashBorrower, address(asset), IDLE_LIQUIDITY, "");
    }

    /// @dev Puts underlying into the pool the way an inflow does: sent to the pool and booked as idle liquidity.
    ///      Sending it alone is a donation, which the pool does not account for.
    function _seedIdleLiquidity(BorrowableHarness targetPool, uint256 assets) internal {
        asset.mint(address(targetPool), assets);
        targetPool.seedIdleLiquidity(assets);
    }

    function _mintAndApprove(BorrowableHarness targetPool, address account, uint256 amount) internal {
        asset.mint(account, amount);
        vm.prank(account);
        asset.approve(address(targetPool), amount);
    }

    function _deployBorrowableHarness() internal returns (BorrowableHarness testPool, MockDebtToken testDebtToken) {
        BorrowableHarness implementation = new BorrowableHarness();
        testPool = BorrowableHarness(Clones.clone(address(implementation)));
        testDebtToken = new MockDebtToken(address(testPool), asset.decimals());
        testPool.initialize(
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
            POOL_NAME,
            POOL_SYMBOL,
            address(testDebtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );
    }

    function _deployExitPosition(address owner)
        internal
        returns (BorrowableHarness testPool, MockDebtToken testDebtToken)
    {
        (testPool, testDebtToken) = _deployBorrowableHarness();
        testPool.seedShares(owner, EXIT_POSITION_SHARES);
        _seedIdleLiquidity(testPool, EXIT_POSITION_ASSETS);
    }

    /// @dev Prices the pool at exactly one asset per share with `MAX_DEPOSIT_ROOM` shares left under the cap.
    function _deployMaxDepositRoomPosition() internal returns (BorrowableHarness testPool) {
        (testPool,) = _deployBorrowableHarness();
        testPool.seedShares(other, ShareMath.MAX_DEPOSIT_SHARES - MAX_DEPOSIT_ROOM);
        _seedIdleLiquidity(testPool, ShareMath.MAX_DEPOSIT_SHARES - MAX_DEPOSIT_ROOM);
    }

    function _deployTransferPosition() internal returns (BorrowableHarness testPool) {
        (testPool,) = _deployBorrowableHarness();
        testPool.seedShares(caller, TRANSFER_POSITION_SHARES);
    }

    function _configureHooks(uint256 beforeBitmap, uint256 afterBitmap) internal {
        _configureHooks(pool, beforeBitmap, afterBitmap);
    }

    function _configureHooks(BorrowableHarness targetPool, uint256 beforeBitmap, uint256 afterBitmap) internal {
        vm.startPrank(hookUpdater);
        targetPool.setHookReceiver(address(hookReceiver));
        targetPool.setHookBitmaps(beforeBitmap, afterBitmap);
        vm.stopPrank();
    }
}
