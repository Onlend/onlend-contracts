// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBorrowable} from "src/pool/interfaces/IBorrowable.sol";
import {ICollateralisable} from "src/pool/interfaces/ICollateralisable.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {CollateralToken} from "src/pool/collateral/abstract/CollateralToken.sol";
import {Collateralisable} from "src/pool/abstract/Collateralisable.sol";
import {Borrowable} from "src/pool/abstract/Borrowable.sol";
import {BorrowableCollateralToken} from "src/pool/collateral/BorrowableCollateralToken.sol";
import {IDebtToken} from "src/pool/debt/interfaces/IDebtToken.sol";
import {CollateralisableBorrowablePool} from "src/pool/CollateralisableBorrowablePool.sol";
import {ShareMath} from "src/pool/lib/ShareMath.sol";
import {MockHookReceiver} from "../hooks/mocks/MockHookReceiver.sol";
import {MockDebtToken} from "./mocks/MockDebtToken.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockOnlendFeeRegistry} from "./mocks/MockOnlendFeeRegistry.sol";
import {CollateralisableBorrowablePoolHarness} from "./mocks/CollateralisableBorrowablePoolHarness.sol";

contract CollateralisableBorrowablePoolUnitTest is Test {
    CollateralisableBorrowablePoolHarness internal pool;
    MockERC20 internal asset;
    MockDebtToken internal debtToken;
    MockOnlendFeeRegistry internal feeRegistry;
    MockHookReceiver internal hookReceiver;
    CollateralToken internal collateralToken;

    address internal defaultAdmin = makeAddr("defaultAdmin");
    address internal hookUpdater = makeAddr("hookUpdater");
    address internal flashLoanConfigurator = makeAddr("flashLoanConfigurator");
    address internal operatorFeeConfigurator = makeAddr("operatorFeeConfigurator");
    address internal operatorFeeRecipient = makeAddr("operatorFeeRecipient");
    address internal lendingCore = makeAddr("lendingCore");
    address internal caller = makeAddr("caller");
    address internal receiver = makeAddr("receiver");
    address internal other = makeAddr("other");
    address internal borrower = makeAddr("borrower");
    address internal operator = makeAddr("operator");

    string internal constant POOL_NAME = "fOnlend USD Coin";
    string internal constant POOL_SYMBOL = "fOnlend USDC";
    string internal constant COLLATERAL_TOKEN_NAME = "USD Coin";
    string internal constant COLLATERAL_TOKEN_SYMBOL = "USDC";
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
    uint256 internal constant COLLATERAL_DEPOSIT_ASSETS = 1000;
    uint256 internal constant COLLATERAL_DEPOSIT_SHARES = 1000;
    uint256 internal constant MAX_DEPOSIT_ROOM = 1000;
    uint256 internal constant COLLATERAL_POSITION_ASSETS = 1000;
    uint256 internal constant COLLATERAL_POSITION_SHARES = 1000;
    uint256 internal constant COLLATERAL_WITHDRAW_ASSETS = 400;
    uint256 internal constant COLLATERAL_REDEEM_SHARES = 400;
    uint256 internal constant COLLATERAL_SEIZE_ASSETS = 400;
    uint256 internal constant BORROW_LIQUIDITY = 1000;
    uint256 internal constant BORROW_AMOUNT = 400;
    uint256 internal constant REPAY_IDLE_LIQUIDITY = 1000;
    uint256 internal constant REPAY_DEBT = 600;
    uint256 internal constant REPAY_AMOUNT = 400;

    function setUp() public {
        asset = new MockERC20();
        hookReceiver = new MockHookReceiver();
        feeRegistry = new MockOnlendFeeRegistry(makeAddr("onlendFeeRecipient"));
        CollateralisableBorrowablePoolHarness implementation = new CollateralisableBorrowablePoolHarness();
        pool = CollateralisableBorrowablePoolHarness(Clones.clone(address(implementation)));
        (collateralToken, debtToken) = _deployPoolTokens(address(pool));
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
            address(collateralToken),
            address(debtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );
    }

    // initialize()

    function test_initialize_ConfiguresPoolRolesAndLendingCore() public view {
        assertTrue(pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(pool.hasRole(pool.HOOK_UPDATER_ROLE(), hookUpdater));
        assertTrue(pool.hasRole(pool.OPERATOR_FEE_CONFIG_ROLE(), operatorFeeConfigurator));
        assertEq(pool.lendingCore(), lendingCore);
    }

    function test_initialize_AllowsZeroAddressRoleMembers() public {
        CollateralisableBorrowablePool implementation = new CollateralisableBorrowablePool();
        CollateralisableBorrowablePool rolelessPool =
            CollateralisableBorrowablePool(Clones.clone(address(implementation)));
        (CollateralToken testCollateralToken, MockDebtToken testDebtToken) = _deployPoolTokens(address(rolelessPool));

        rolelessPool.initialize(
            address(0),
            address(0),
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
            address(testCollateralToken),
            address(testDebtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );

        assertEq(rolelessPool.getRoleMemberCount(rolelessPool.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(rolelessPool.getRoleMemberCount(rolelessPool.HOOK_UPDATER_ROLE()), 0);
        assertEq(rolelessPool.getRoleMemberCount(rolelessPool.OPERATOR_FEE_CONFIG_ROLE()), 0);
    }

    function test_initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(pool.getRoleAdmin(pool.HOOK_UPDATER_ROLE()), pool.DEFAULT_ADMIN_ROLE());
    }

    function test_initialize_ConfiguresPoolShareTokenAndUnderlying() public view {
        assertEq(pool.name(), POOL_NAME);
        assertEq(pool.symbol(), POOL_SYMBOL);
        assertEq(pool.decimals(), asset.decimals());
        assertEq(pool.asset(), address(asset));
    }

    function test_initialize_WiresBorrowableDependencies() public view {
        assertEq(pool.debtToken(), address(debtToken));
        assertEq(pool.feeRegistry(), address(feeRegistry));
        assertEq(pool.operatorFeeRecipient(), operatorFeeRecipient);
    }

    function test_initialize_EmitsPoolInitialised() public {
        CollateralisableBorrowablePool instance =
            CollateralisableBorrowablePool(Clones.clone(address(new CollateralisableBorrowablePool())));
        (CollateralToken testCollateralToken, MockDebtToken testDebtToken) = _deployPoolTokens(address(instance));

        vm.expectEmit(address(instance));
        emit CollateralisableBorrowablePool.PoolInitialised(
            lendingCore, address(asset), address(testCollateralToken), address(testDebtToken)
        );

        instance.initialize(
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
            address(testCollateralToken),
            address(testDebtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(pool.contractName(), "CollateralisableBorrowablePool");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(pool.contractVersion(), "1.0.0");
    }

    // totalCollateral()

    function test_totalCollateral_ReturnsCollateralInUnderlyingAssets() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(other, 999_900);
        testPool.seedCollateralPosition(caller, 100);
        _seedIdleLiquidity(testPool, 3e6);

        // 100 collateral shares at two assets per share represent 200 assets.
        assertEq(testPool.totalCollateral(), 200);
    }

    // collateralOf()

    function test_collateralOf_ReturnsEachAccountsCollateralInUnderlyingAssets() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(other, 999_850);
        testPool.seedCollateralPosition(caller, 100);
        testPool.seedCollateralPosition(receiver, 50);
        _seedIdleLiquidity(testPool, 3e6);

        // At two assets per share, 100 collateral shares represent 200 assets and 50 represent 100.
        assertEq(testPool.collateralOf(caller), 200);
        assertEq(testPool.collateralOf(receiver), 100);
    }

    // debtOf()

    function test_debtOf_ReturnsEachAccountsDebt() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testDebtToken.seedDebt(caller, 500e18);
        testDebtToken.seedDebt(receiver, 100e18);

        assertEq(testPool.debtOf(caller), 500e18);
        assertEq(testPool.debtOf(receiver), 100e18);
    }

    // supportsInterface()

    function test_supportsInterface_ReturnsTrueForBorrowable() public view {
        assertTrue(pool.supportsInterface(type(IBorrowable).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForCollateralisable() public view {
        assertTrue(pool.supportsInterface(type(ICollateralisable).interfaceId));
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

    // _depositCollateral()

    function test_depositCollateral_RevertsWhenAssetsAndSharesAreZero() public {
        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.depositCollateral(caller, 0, 0, receiver);
    }

    function test_depositCollateral_RevertsWhenAssetsAndSharesAreNonZero() public {
        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.depositCollateral(caller, COLLATERAL_DEPOSIT_ASSETS, COLLATERAL_DEPOSIT_SHARES, receiver);
    }

    function test_depositCollateral_WithAssetsTransfersAssetsFromCaller() public {
        _mintAndApprove(pool, caller, COLLATERAL_DEPOSIT_ASSETS);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, COLLATERAL_DEPOSIT_ASSETS, 0, receiver);

        assertEq(asset.balanceOf(caller), 0);
        assertEq(asset.balanceOf(address(pool)), COLLATERAL_DEPOSIT_ASSETS);
    }

    function test_depositCollateral_BooksAssetsAsIdleLiquidity() public {
        _mintAndApprove(pool, caller, COLLATERAL_DEPOSIT_ASSETS);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, COLLATERAL_DEPOSIT_ASSETS, 0, receiver);

        assertEq(pool.idleLiquidity(), COLLATERAL_DEPOSIT_ASSETS);
    }

    function test_depositCollateral_WithAssetsMintsCalculatedCollateralShares() public {
        _mintAndApprove(pool, caller, COLLATERAL_DEPOSIT_ASSETS);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, COLLATERAL_DEPOSIT_ASSETS, 0, receiver);

        assertEq(collateralToken.balanceOf(receiver), COLLATERAL_DEPOSIT_ASSETS);
    }

    function test_depositCollateral_WithSharesMintsRequestedCollateralShares() public {
        _mintAndApprove(pool, caller, COLLATERAL_DEPOSIT_SHARES);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, 0, COLLATERAL_DEPOSIT_SHARES, receiver);

        assertEq(collateralToken.balanceOf(receiver), COLLATERAL_DEPOSIT_SHARES);
    }

    function test_depositCollateral_WithSharesTransfersRequiredAssetsFromCaller() public {
        _mintAndApprove(pool, caller, COLLATERAL_DEPOSIT_SHARES);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, 0, COLLATERAL_DEPOSIT_SHARES, receiver);

        assertEq(asset.balanceOf(caller), 0);
        assertEq(asset.balanceOf(address(pool)), COLLATERAL_DEPOSIT_SHARES);
    }

    function test_depositCollateral_WithAssetsPricesSharesUsingOutstandingDebt() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(other, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);
        _mintAndApprove(testPool, caller, 200);
        CollateralToken testCollateralToken = CollateralToken(testPool.collateralToken());

        vm.prank(lendingCore);
        testPool.depositCollateral(caller, 200, 0, receiver);

        // 1,000,000 shares against 3,000,000 assets, each side lifted by the virtual pair, prices the
        // pool at exactly 4,000,000 / 2,000,000 = two assets per share.
        assertEq(testCollateralToken.balanceOf(receiver), 100);
    }

    function test_depositCollateral_WithSharesPricesAssetsUsingOutstandingDebt() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(other, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);
        _mintAndApprove(testPool, caller, 200);

        vm.prank(lendingCore);
        testPool.depositCollateral(caller, 0, 100, receiver);

        // One hundred shares cost exactly 200 assets at the two-assets-per-share price, on top of the 2,000,000 idle.
        assertEq(asset.balanceOf(address(testPool)), 2_000_200);
    }

    function test_depositCollateral_WithAssetsReturnsRequestedAssetsAndDerivedShares() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(other, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);
        _mintAndApprove(testPool, caller, 200);

        vm.prank(lendingCore);
        (uint256 assetsDeposited, uint256 sharesMinted) = testPool.depositCollateral(caller, 200, 0, receiver);

        // 200 assets buy 100 shares at the two-assets-per-share price.
        assertEq(assetsDeposited, 200);
        assertEq(sharesMinted, 100);
    }

    function test_depositCollateral_WithSharesReturnsDerivedAssetsAndRequestedShares() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(other, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);
        _mintAndApprove(testPool, caller, 200);

        vm.prank(lendingCore);
        (uint256 assetsDeposited, uint256 sharesMinted) = testPool.depositCollateral(caller, 0, 100, receiver);

        // 100 shares cost 200 assets at the two-assets-per-share price.
        assertEq(assetsDeposited, 200);
        assertEq(sharesMinted, 100);
    }

    function test_depositCollateral_WithAssetsRoundsSharesDown() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(other, 2);
        testDebtToken.seedDebt(borrower, 3);
        _mintAndApprove(testPool, caller, 2);
        CollateralToken testCollateralToken = CollateralToken(testPool.collateralToken());

        vm.prank(lendingCore);
        testPool.depositCollateral(caller, 2, 0, receiver);

        // floor(2 assets * 1,000,002 adjusted shares / 1,000,003 adjusted assets) = 1 share.
        assertEq(testCollateralToken.balanceOf(receiver), 1);
    }

    function test_depositCollateral_WithSharesRoundsAssetsUp() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(other, 2);
        testDebtToken.seedDebt(borrower, 3);
        _mintAndApprove(testPool, caller, 2);

        vm.prank(lendingCore);
        testPool.depositCollateral(caller, 0, 1, receiver);

        // ceil(1 share * 1,000,003 adjusted assets / 1,000,002 adjusted shares) = 2 assets.
        assertEq(asset.balanceOf(address(testPool)), 2);
    }

    function test_depositCollateral_WithAssetsAcceptsAssetsWhoseSharesReachMaxDepositShares() public {
        CollateralisableBorrowablePoolHarness testPool = _deployMaxDepositRoomPosition();
        _mintAndApprove(testPool, caller, MAX_DEPOSIT_ROOM);

        vm.prank(lendingCore);
        testPool.depositCollateral(caller, MAX_DEPOSIT_ROOM, 0, receiver);

        assertEq(testPool.totalSupply(), ShareMath.MAX_DEPOSIT_SHARES);
    }

    function test_depositCollateral_WithSharesAcceptsSharesReachingMaxDepositShares() public {
        CollateralisableBorrowablePoolHarness testPool = _deployMaxDepositRoomPosition();
        _mintAndApprove(testPool, caller, MAX_DEPOSIT_ROOM);

        vm.prank(lendingCore);
        testPool.depositCollateral(caller, 0, MAX_DEPOSIT_ROOM, receiver);

        assertEq(testPool.totalSupply(), ShareMath.MAX_DEPOSIT_SHARES);
    }

    function test_depositCollateral_WithAssetsRevertsWhenSharesWouldExceedMaxDepositShares() public {
        CollateralisableBorrowablePoolHarness testPool = _deployMaxDepositRoomPosition();
        _mintAndApprove(testPool, caller, MAX_DEPOSIT_ROOM + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxDeposit.selector, address(testPool), MAX_DEPOSIT_ROOM + 1, MAX_DEPOSIT_ROOM
            )
        );
        vm.prank(lendingCore);
        testPool.depositCollateral(caller, MAX_DEPOSIT_ROOM + 1, 0, receiver);
    }

    function test_depositCollateral_WithSharesRevertsWhenSharesWouldExceedMaxDepositShares() public {
        CollateralisableBorrowablePoolHarness testPool = _deployMaxDepositRoomPosition();
        _mintAndApprove(testPool, caller, MAX_DEPOSIT_ROOM + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxMint.selector, address(testPool), MAX_DEPOSIT_ROOM + 1, MAX_DEPOSIT_ROOM
            )
        );
        vm.prank(lendingCore);
        testPool.depositCollateral(caller, 0, MAX_DEPOSIT_ROOM + 1, receiver);
    }

    function test_depositCollateral_RevertsWhenPositiveAssetsWouldMintZeroShares() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(other, 1);
        testDebtToken.seedDebt(borrower, 3);

        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(lendingCore);
        testPool.depositCollateral(caller, 1, 0, receiver);
    }

    function test_depositCollateral_BacksCollateralTokensWithPoolShares() public {
        _mintAndApprove(pool, caller, COLLATERAL_DEPOSIT_ASSETS);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, COLLATERAL_DEPOSIT_ASSETS, 0, receiver);

        assertEq(pool.balanceOf(address(pool)), COLLATERAL_DEPOSIT_ASSETS);
        assertEq(collateralToken.totalSupply(), pool.balanceOf(address(pool)));
    }

    function test_depositCollateral_ExecutesInterestAccountingAndCollateralMintInOrder() public {
        _mintAndApprove(pool, caller, COLLATERAL_DEPOSIT_ASSETS);

        vm.expectEmit(address(debtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(pool));
        emit IERC4626.Deposit(caller, address(pool), COLLATERAL_DEPOSIT_ASSETS, COLLATERAL_DEPOSIT_ASSETS);
        vm.expectEmit(address(collateralToken));
        emit IERC20.Transfer(address(0), receiver, COLLATERAL_DEPOSIT_ASSETS);
        vm.expectEmit(address(debtToken));
        emit MockDebtToken.UpdateBorrowRatesCalled(COLLATERAL_DEPOSIT_ASSETS);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, COLLATERAL_DEPOSIT_ASSETS, 0, receiver);
    }

    function test_depositCollateral_RecomputesBorrowRatesOnUpdatedIdleLiquidity() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(other, 1000);
        _seedIdleLiquidity(testPool, 500);
        testDebtToken.seedDebt(borrower, 500);
        _mintAndApprove(testPool, caller, COLLATERAL_DEPOSIT_ASSETS);

        // The 500 already idle plus the 1,000 escrowed as collateral.
        vm.expectCall(address(testDebtToken), abi.encodeCall(IDebtToken.updateBorrowRates, (1500)), 1);
        vm.prank(lendingCore);
        testPool.depositCollateral(caller, COLLATERAL_DEPOSIT_ASSETS, 0, receiver);
    }

    // _withdrawCollateral()

    function test_withdrawCollateral_RevertsWhenAssetsAndSharesAreZero() public {
        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, 0, 0, receiver);
    }

    function test_withdrawCollateral_RevertsWhenAssetsAndSharesAreNonZero() public {
        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, COLLATERAL_WITHDRAW_ASSETS, COLLATERAL_REDEEM_SHARES, receiver);
    }

    function test_withdrawCollateral_WithAssetsTransfersRequestedAssetsToReceiver() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralPosition(caller);

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, COLLATERAL_WITHDRAW_ASSETS, 0, receiver);

        assertEq(asset.balanceOf(receiver), COLLATERAL_WITHDRAW_ASSETS);
        assertEq(asset.balanceOf(address(testPool)), COLLATERAL_POSITION_ASSETS - COLLATERAL_WITHDRAW_ASSETS);
    }

    function test_withdrawCollateral_ReleasesAssetsFromIdleLiquidity() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralPosition(caller);

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, COLLATERAL_WITHDRAW_ASSETS, 0, receiver);

        assertEq(testPool.idleLiquidity(), COLLATERAL_POSITION_ASSETS - COLLATERAL_WITHDRAW_ASSETS);
    }

    function test_withdrawCollateral_WithAssetsBurnsCalculatedCollateralShares() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralPosition(caller);
        CollateralToken testCollateralToken = CollateralToken(testPool.collateralToken());

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, COLLATERAL_WITHDRAW_ASSETS, 0, receiver);

        assertEq(testCollateralToken.balanceOf(caller), COLLATERAL_POSITION_SHARES - COLLATERAL_WITHDRAW_ASSETS);
    }

    function test_withdrawCollateral_WithSharesBurnsRequestedCollateralShares() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralPosition(caller);
        CollateralToken testCollateralToken = CollateralToken(testPool.collateralToken());

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, 0, COLLATERAL_REDEEM_SHARES, receiver);

        assertEq(testCollateralToken.balanceOf(caller), COLLATERAL_POSITION_SHARES - COLLATERAL_REDEEM_SHARES);
    }

    function test_withdrawCollateral_WithSharesTransfersCalculatedAssetsToReceiver() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralPosition(caller);

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, 0, COLLATERAL_REDEEM_SHARES, receiver);

        assertEq(asset.balanceOf(receiver), COLLATERAL_REDEEM_SHARES);
    }

    function test_withdrawCollateral_WithAssetsPricesSharesUsingOutstandingDebt() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);
        CollateralToken testCollateralToken = CollateralToken(testPool.collateralToken());

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, 200, 0, receiver);

        // 200 assets cost 100 shares at the two-assets-per-share price, leaving the position 100 short.
        assertEq(testCollateralToken.balanceOf(caller), 999_900);
    }

    function test_withdrawCollateral_WithSharesPricesAssetsUsingOutstandingDebt() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, 0, 100, receiver);

        // One hundred shares return exactly 200 assets at the two-assets-per-share price.
        assertEq(asset.balanceOf(receiver), 200);
    }

    function test_withdrawCollateral_WithAssetsReturnsRequestedAssetsAndDerivedShares() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);

        vm.prank(lendingCore);
        (uint256 assetsWithdrawn, uint256 sharesBurned) = testPool.withdrawCollateral(caller, 200, 0, receiver);

        // 200 assets cost 100 shares at the two-assets-per-share price.
        assertEq(assetsWithdrawn, 200);
        assertEq(sharesBurned, 100);
    }

    function test_withdrawCollateral_WithSharesReturnsDerivedAssetsAndRequestedShares() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);

        vm.prank(lendingCore);
        (uint256 assetsWithdrawn, uint256 sharesBurned) = testPool.withdrawCollateral(caller, 0, 100, receiver);

        // 100 shares return 200 assets at the two-assets-per-share price.
        assertEq(assetsWithdrawn, 200);
        assertEq(sharesBurned, 100);
    }

    function test_withdrawCollateral_WithAssetsRoundsSharesUp() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 2);
        _seedIdleLiquidity(testPool, 3);
        CollateralToken testCollateralToken = CollateralToken(testPool.collateralToken());

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, 1, 0, receiver);

        // ceil(1 asset * 1,000,002 adjusted shares / 1,000,003 adjusted assets) = 1 share.
        assertEq(testCollateralToken.balanceOf(caller), 1);
    }

    function test_withdrawCollateral_WithSharesRoundsAssetsDown() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 2);
        _seedIdleLiquidity(testPool, 3);

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, 0, 1, receiver);

        // floor(1 share * 1,000,003 adjusted assets / 1,000,002 adjusted shares) = 1 asset.
        assertEq(asset.balanceOf(receiver), 1);
    }

    function test_withdrawCollateral_RevertsWhenPositiveSharesWouldReturnZeroAssets() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 3);
        _seedIdleLiquidity(testPool, 1);

        // floor(1 share * 1,000,001 adjusted assets / 1,000,003 adjusted shares) = 0 assets.
        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, 0, 1, receiver);
    }

    function test_withdrawCollateral_AllowsAssetsAtAvailableLiquidityLimit() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 1000);
        _seedIdleLiquidity(testPool, 400);
        testDebtToken.seedDebt(borrower, 600);

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, 400, 0, receiver);

        assertEq(asset.balanceOf(receiver), 400);
    }

    function test_withdrawCollateral_RevertsWhenAssetsExceedAvailableLiquidity() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 1000);
        _seedIdleLiquidity(testPool, 400);
        testDebtToken.seedDebt(borrower, 600);

        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, address(testPool), 401, 400)
        );
        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, 401, 0, receiver);
    }

    function test_withdrawCollateral_AllowsSharesAtAvailableLiquidityLimit() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 1000);
        _seedIdleLiquidity(testPool, 400);
        testDebtToken.seedDebt(borrower, 600);

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, 0, 400, receiver);

        assertEq(asset.balanceOf(receiver), 400);
    }

    function test_withdrawCollateral_RevertsWhenSharesExceedAvailableLiquidity() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 1000);
        _seedIdleLiquidity(testPool, 400);
        testDebtToken.seedDebt(borrower, 600);

        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxRedeem.selector, address(testPool), 401, 400));
        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, 0, 401, receiver);
    }

    function test_withdrawCollateral_KeepsCollateralTokensBackedByPoolShares() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralPosition(caller);
        CollateralToken testCollateralToken = CollateralToken(testPool.collateralToken());

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, COLLATERAL_WITHDRAW_ASSETS, 0, receiver);

        assertEq(testPool.balanceOf(address(testPool)), COLLATERAL_POSITION_SHARES - COLLATERAL_WITHDRAW_ASSETS);
        assertEq(testCollateralToken.totalSupply(), testPool.balanceOf(address(testPool)));
    }

    function test_withdrawCollateral_ExecutesCollateralBurnAndInterestAccountingInOrder() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralPosition(caller);
        CollateralToken testCollateralToken = CollateralToken(testPool.collateralToken());

        vm.expectEmit(address(testDebtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(testCollateralToken));
        emit IERC20.Transfer(caller, address(0), COLLATERAL_WITHDRAW_ASSETS);
        vm.expectEmit(address(testPool));
        emit IERC4626.Withdraw(
            address(testPool), receiver, address(testPool), COLLATERAL_WITHDRAW_ASSETS, COLLATERAL_WITHDRAW_ASSETS
        );
        vm.expectEmit(address(testDebtToken));
        emit MockDebtToken.UpdateBorrowRatesCalled(COLLATERAL_POSITION_ASSETS - COLLATERAL_WITHDRAW_ASSETS);

        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, COLLATERAL_WITHDRAW_ASSETS, 0, receiver);
    }

    function test_withdrawCollateral_RecomputesBorrowRatesOnUpdatedIdleLiquidity() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 1000);
        _seedIdleLiquidity(testPool, 500);
        testDebtToken.seedDebt(borrower, 500);

        // 1,000 assets back 1,000 shares, so the 500 idle less the 400 released.
        vm.expectCall(address(testDebtToken), abi.encodeCall(IDebtToken.updateBorrowRates, (100)), 1);
        vm.prank(lendingCore);
        testPool.withdrawCollateral(caller, COLLATERAL_WITHDRAW_ASSETS, 0, receiver);
    }

    // _seizeCollateral()

    function test_seizeCollateral_RevertsWhenAssetsAreZero() public {
        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.seizeCollateral(caller, 0, receiver);
    }

    function test_seizeCollateral_BurnsCalculatedCollateralShares() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralPosition(caller);
        CollateralToken testCollateralToken = CollateralToken(testPool.collateralToken());

        vm.prank(lendingCore);
        testPool.seizeCollateral(caller, COLLATERAL_SEIZE_ASSETS, receiver);

        assertEq(testCollateralToken.balanceOf(caller), COLLATERAL_POSITION_SHARES - COLLATERAL_SEIZE_ASSETS);
    }

    function test_seizeCollateral_TransfersEscrowedSharesToReceiver() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralPosition(caller);

        vm.prank(lendingCore);
        testPool.seizeCollateral(caller, COLLATERAL_SEIZE_ASSETS, receiver);

        assertEq(testPool.balanceOf(receiver), COLLATERAL_SEIZE_ASSETS);
        assertEq(testPool.balanceOf(address(testPool)), COLLATERAL_POSITION_SHARES - COLLATERAL_SEIZE_ASSETS);
    }

    function test_seizeCollateral_KeepsCollateralTokensBackedByPoolShares() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralPosition(caller);
        CollateralToken testCollateralToken = CollateralToken(testPool.collateralToken());

        vm.prank(lendingCore);
        testPool.seizeCollateral(caller, COLLATERAL_SEIZE_ASSETS, receiver);

        assertEq(testCollateralToken.totalSupply(), testPool.balanceOf(address(testPool)));
    }

    function test_seizeCollateral_PricesSharesUsingOutstandingDebt() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);
        CollateralToken testCollateralToken = CollateralToken(testPool.collateralToken());

        vm.prank(lendingCore);
        testPool.seizeCollateral(caller, 200, receiver);

        // 200 assets cost 100 shares at the two-assets-per-share price, leaving the position 100 short.
        assertEq(testCollateralToken.balanceOf(caller), 999_900);
        assertEq(testPool.balanceOf(receiver), 100);
    }

    function test_seizeCollateral_ReturnsSeizedAssetsAndTransferredShares() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 1e6);
        _seedIdleLiquidity(testPool, 2e6);
        testDebtToken.seedDebt(borrower, 1e6);

        vm.prank(lendingCore);
        (uint256 assetsSeized, uint256 sharesSeized) = testPool.seizeCollateral(caller, 200, receiver);

        // 200 assets price to the 100 shares the receiver is paid in, at the two-assets-per-share price.
        assertEq(assetsSeized, 200);
        assertEq(sharesSeized, 100);
    }

    function test_seizeCollateral_RoundsSharesUp() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(caller, 2);
        _seedIdleLiquidity(testPool, 3);

        vm.prank(lendingCore);
        testPool.seizeCollateral(caller, 1, receiver);

        // ceil(1 asset * 1,000,002 adjusted shares / 1,000,003 adjusted assets) = 1 share.
        assertEq(testPool.balanceOf(receiver), 1);
    }

    function test_seizeCollateral_RevertsWhenSharesExceedTheViolatorsCollateral() public {
        (CollateralisableBorrowablePoolHarness testPool,) = _deployCollateralPosition(caller);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                caller,
                COLLATERAL_POSITION_SHARES,
                COLLATERAL_POSITION_SHARES + 1
            )
        );
        vm.prank(lendingCore);
        testPool.seizeCollateral(caller, COLLATERAL_POSITION_ASSETS + 1, receiver);
    }

    function test_seizeCollateral_ExecutesCollateralBurnAndInterestAccountingInOrder() public {
        (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken) =
            _deployCollateralPosition(caller);
        CollateralToken testCollateralToken = CollateralToken(testPool.collateralToken());

        vm.expectEmit(address(testDebtToken));
        emit MockDebtToken.AccrueInterestCalled();
        vm.expectEmit(address(testCollateralToken));
        emit IERC20.Transfer(caller, address(0), COLLATERAL_SEIZE_ASSETS);
        vm.expectEmit(address(testPool));
        emit IERC20.Transfer(address(testPool), receiver, COLLATERAL_SEIZE_ASSETS);
        vm.expectEmit(address(testDebtToken));
        emit MockDebtToken.UpdateBorrowRatesCalled(COLLATERAL_POSITION_ASSETS);

        vm.prank(lendingCore);
        testPool.seizeCollateral(caller, COLLATERAL_SEIZE_ASSETS, receiver);
    }

    /// @dev Puts underlying into the pool the way an inflow does: sent to the pool and booked as idle liquidity.
    ///      Sending it alone is a donation, which the pool does not account for.
    function _seedIdleLiquidity(CollateralisableBorrowablePoolHarness targetPool, uint256 assets) internal {
        asset.mint(address(targetPool), assets);
        targetPool.seedIdleLiquidity(assets);
    }

    function _mintAndApprove(CollateralisableBorrowablePool targetPool, address account, uint256 amount) internal {
        asset.mint(account, amount);
        vm.prank(account);
        asset.approve(address(targetPool), amount);
    }

    function _deployCollateralisableBorrowablePoolHarness()
        internal
        returns (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken)
    {
        CollateralisableBorrowablePoolHarness implementation = new CollateralisableBorrowablePoolHarness();
        testPool = CollateralisableBorrowablePoolHarness(Clones.clone(address(implementation)));
        (CollateralToken testCollateralToken, MockDebtToken deployedDebtToken) = _deployPoolTokens(address(testPool));
        testDebtToken = deployedDebtToken;
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
            address(testCollateralToken),
            address(testDebtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );
    }

    function _deployPoolTokens(address targetPool)
        internal
        returns (CollateralToken testCollateralToken, MockDebtToken testDebtToken)
    {
        BorrowableCollateralToken collateralImplementation = new BorrowableCollateralToken();
        BorrowableCollateralToken collateralClone =
            BorrowableCollateralToken(Clones.clone(address(collateralImplementation)));
        collateralClone.initialize(targetPool, COLLATERAL_TOKEN_NAME, COLLATERAL_TOKEN_SYMBOL, asset.decimals());
        testCollateralToken = collateralClone;

        testDebtToken = new MockDebtToken(targetPool, asset.decimals());
    }

    function _deployExitPosition(address owner)
        internal
        returns (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken)
    {
        (testPool, testDebtToken) = _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(owner, EXIT_POSITION_SHARES);
        _seedIdleLiquidity(testPool, EXIT_POSITION_ASSETS);
    }

    function _deployTransferPosition() internal returns (CollateralisableBorrowablePoolHarness testPool) {
        (testPool,) = _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(caller, TRANSFER_POSITION_SHARES);
    }

    /// @dev Prices the pool at exactly one asset per share with `MAX_DEPOSIT_ROOM` shares left under the cap.
    function _deployMaxDepositRoomPosition() internal returns (CollateralisableBorrowablePoolHarness testPool) {
        (testPool,) = _deployCollateralisableBorrowablePoolHarness();
        testPool.seedShares(other, ShareMath.MAX_DEPOSIT_SHARES - MAX_DEPOSIT_ROOM);
        _seedIdleLiquidity(testPool, ShareMath.MAX_DEPOSIT_SHARES - MAX_DEPOSIT_ROOM);
    }

    function _deployCollateralPosition(address owner)
        internal
        returns (CollateralisableBorrowablePoolHarness testPool, MockDebtToken testDebtToken)
    {
        (testPool, testDebtToken) = _deployCollateralisableBorrowablePoolHarness();
        testPool.seedCollateralPosition(owner, COLLATERAL_POSITION_SHARES);
        _seedIdleLiquidity(testPool, COLLATERAL_POSITION_ASSETS);
    }

    function _configureHooks(uint256 beforeBitmap, uint256 afterBitmap) internal {
        _configureHooks(pool, beforeBitmap, afterBitmap);
    }

    function _configureHooks(CollateralisableBorrowablePool targetPool, uint256 beforeBitmap, uint256 afterBitmap)
        internal
    {
        vm.startPrank(hookUpdater);
        targetPool.setHookReceiver(address(hookReceiver));
        targetPool.setHookBitmaps(beforeBitmap, afterBitmap);
        vm.stopPrank();
    }
}
