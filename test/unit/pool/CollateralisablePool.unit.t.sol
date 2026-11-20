// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {CollateralToken} from "src/pool/collateral/abstract/CollateralToken.sol";
import {ProtectedCollateralToken} from "src/pool/collateral/ProtectedCollateralToken.sol";
import {BasePool} from "src/pool/abstract/BasePool.sol";
import {Collateralisable} from "src/pool/abstract/Collateralisable.sol";
import {CollateralisablePool} from "src/pool/CollateralisablePool.sol";
import {MockCollateralToken} from "./mocks/MockCollateralToken.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract CollateralisablePoolTest is Test {
    CollateralisablePool pool;
    MockERC20 asset;
    ProtectedCollateralToken configuredCollateralToken;

    address defaultAdmin = makeAddr("defaultAdmin");
    address hookUpdater = makeAddr("hookUpdater");
    address flashLoanConfigurator = makeAddr("flashLoanConfigurator");
    address lendingCore = makeAddr("lendingCore");
    address caller = makeAddr("caller");
    address receiver = makeAddr("receiver");
    address other = makeAddr("other");
    address violator = makeAddr("violator");

    string constant COLLATERAL_NAME = "Protected USD Coin";
    string constant COLLATERAL_SYMBOL = "pUSDC";
    uint256 constant AMOUNT = 250e18;
    uint256 constant OTHER_AMOUNT = 100e18;
    uint256 constant MIN_AMOUNT = 1;
    uint256 constant PARTIAL_AMOUNT = 75e18;

    function setUp() public {
        asset = new MockERC20();
        (pool, configuredCollateralToken) = _deployCollateralisablePool(defaultAdmin, hookUpdater, lendingCore);
    }

    // initialize()

    function test_Initialize_ConfiguresDefaultAdminHookUpdaterAndLendingCore() public view {
        assertTrue(pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(pool.hasRole(pool.HOOK_UPDATER_ROLE(), hookUpdater));
        assertEq(pool.lendingCore(), lendingCore);
    }

    function test_Initialize_AllowsZeroAddressRoleMembersAndLendingCore() public {
        (CollateralisablePool rolelessPool,) = _deployCollateralisablePool(address(0), address(0), address(0));

        assertEq(rolelessPool.getRoleMemberCount(rolelessPool.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(rolelessPool.getRoleMemberCount(rolelessPool.HOOK_UPDATER_ROLE()), 0);
        assertEq(rolelessPool.lendingCore(), address(0));
    }

    function test_Initialize_EmitsPoolInitialised() public {
        CollateralisablePool instance = CollateralisablePool(Clones.clone(address(new CollateralisablePool())));
        MockCollateralToken collateralToken = new MockCollateralToken(address(instance), 18);

        vm.expectEmit(address(instance));
        emit CollateralisablePool.PoolInitialised(lendingCore, address(asset), address(collateralToken));

        instance.initialize(
            defaultAdmin, hookUpdater, address(0), address(0), 0, 0, lendingCore, false, asset, address(collateralToken)
        );
    }

    function test_Initialize_RevertsWhenCollateralTokenDecimalsDoNotMatchAsset() public {
        CollateralisablePool instance = CollateralisablePool(Clones.clone(address(new CollateralisablePool())));
        MockCollateralToken mismatchedCollateralToken = new MockCollateralToken(address(instance), 6);

        vm.expectRevert(
            abi.encodeWithSelector(BasePool.InvalidTokenDecimals.selector, address(mismatchedCollateralToken), 6, 18)
        );
        instance.initialize(
            defaultAdmin,
            hookUpdater,
            address(0),
            address(0),
            0,
            0,
            lendingCore,
            false,
            asset,
            address(mismatchedCollateralToken)
        );
    }

    // asset()

    function test_Asset_ReturnsUnderlyingAsset() public view {
        assertEq(pool.asset(), address(asset));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(pool.contractName(), "CollateralisablePool");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(pool.contractVersion(), "1.0.0");
    }

    // totalAssets()

    function test_totalAssets_ReturnsTotalProtectedAssets() public {
        _deposit(caller, AMOUNT, receiver);

        assertEq(pool.totalAssets(), AMOUNT);
    }

    // totalCollateral()

    function test_totalCollateral_ReturnsTotalProtectedCollateral() public {
        vm.startPrank(address(pool));
        configuredCollateralToken.mint(caller, AMOUNT);
        configuredCollateralToken.mint(other, OTHER_AMOUNT);
        vm.stopPrank();

        assertEq(pool.totalCollateral(), 350e18);
    }

    // totalDebt()

    function test_totalDebt_ReturnsZeroWhenPoolHasCollateral() public {
        _deposit(caller, AMOUNT, receiver);

        assertEq(pool.totalDebt(), 0);
    }

    // depositCollateral()

    function test_DepositCollateral_TransfersAssetsAndMintsCollateralToken() public {
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        asset.mint(caller, AMOUNT);
        vm.prank(caller);
        asset.approve(address(pool), AMOUNT);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, AMOUNT, 0, receiver);

        assertEq(asset.balanceOf(caller), 0);
        assertEq(asset.balanceOf(receiver), 0);
        assertEq(asset.balanceOf(address(pool)), AMOUNT);
        assertEq(collateralToken.balanceOf(receiver), AMOUNT);
        assertEq(collateralToken.collateralBalanceOf(receiver), AMOUNT);
        assertEq(collateralToken.totalSupply(), AMOUNT);
    }

    function test_DepositCollateral_ReturnsDepositedAssetsAndZeroShares() public {
        asset.mint(caller, AMOUNT);
        vm.prank(caller);
        asset.approve(address(pool), AMOUNT);

        vm.prank(lendingCore);
        (uint256 assetsDeposited, uint256 sharesMinted) = pool.depositCollateral(caller, AMOUNT, 0, receiver);

        assertEq(assetsDeposited, AMOUNT);
        assertEq(sharesMinted, 0);
    }

    function test_DepositCollateral_TransfersAssetsAndMintsCollateralToken_WhenReceiverIsCaller() public {
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        asset.mint(caller, AMOUNT);
        vm.prank(caller);
        asset.approve(address(pool), AMOUNT);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, AMOUNT, 0, caller);

        assertEq(asset.balanceOf(caller), 0);
        assertEq(asset.balanceOf(address(pool)), AMOUNT);
        assertEq(collateralToken.balanceOf(caller), AMOUNT);
        assertEq(collateralToken.collateralBalanceOf(caller), AMOUNT);
        assertEq(collateralToken.totalSupply(), AMOUNT);
    }

    function test_DepositCollateral_TransfersAssetsAndMintsCollateralToken_WhenAssetsIsOne() public {
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        asset.mint(caller, MIN_AMOUNT);
        vm.prank(caller);
        asset.approve(address(pool), MIN_AMOUNT);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, MIN_AMOUNT, 0, receiver);

        assertEq(asset.balanceOf(caller), 0);
        assertEq(asset.balanceOf(receiver), 0);
        assertEq(asset.balanceOf(address(pool)), MIN_AMOUNT);
        assertEq(collateralToken.balanceOf(receiver), MIN_AMOUNT);
        assertEq(collateralToken.collateralBalanceOf(receiver), MIN_AMOUNT);
        assertEq(collateralToken.totalSupply(), MIN_AMOUNT);
    }

    function test_DepositCollateral_AccumulatesCollateralTokenBalance() public {
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        _deposit(caller, AMOUNT, receiver);
        _deposit(caller, OTHER_AMOUNT, receiver);

        assertEq(asset.balanceOf(address(pool)), AMOUNT + OTHER_AMOUNT);
        assertEq(collateralToken.balanceOf(receiver), AMOUNT + OTHER_AMOUNT);
        assertEq(collateralToken.collateralBalanceOf(receiver), AMOUNT + OTHER_AMOUNT);
        assertEq(collateralToken.totalSupply(), AMOUNT + OTHER_AMOUNT);
    }

    function test_DepositCollateral_Revert_WhenAssetsIsZero() public {
        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.depositCollateral(caller, 0, 0, receiver);
    }

    function test_DepositCollateral_Revert_WhenSharesIsNonZero() public {
        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.depositCollateral(caller, AMOUNT, 1, receiver);
    }

    function test_DepositCollateral_Revert_WhenAssetsIsZeroAndSharesIsNonZero() public {
        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.depositCollateral(caller, 0, 1, receiver);
    }

    function test_DepositCollateral_Revert_WhenReceiverIsZero() public {
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        asset.mint(caller, AMOUNT);
        vm.prank(caller);
        asset.approve(address(pool), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(lendingCore);
        pool.depositCollateral(caller, AMOUNT, 0, address(0));

        assertEq(asset.balanceOf(caller), AMOUNT);
        assertEq(asset.balanceOf(address(pool)), 0);
        assertEq(collateralToken.totalSupply(), 0);
    }

    // withdrawCollateral()

    function test_WithdrawCollateral_BurnsCollateralTokenAndTransfersAssets() public {
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        asset.mint(caller, AMOUNT);
        vm.prank(caller);
        asset.approve(address(pool), AMOUNT);
        vm.prank(lendingCore);
        pool.depositCollateral(caller, AMOUNT, 0, caller);

        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, AMOUNT, 0, receiver);

        assertEq(collateralToken.balanceOf(caller), 0);
        assertEq(collateralToken.collateralBalanceOf(caller), 0);
        assertEq(collateralToken.totalSupply(), 0);
        assertEq(asset.balanceOf(address(pool)), 0);
        assertEq(asset.balanceOf(receiver), AMOUNT);
    }

    function test_WithdrawCollateral_ReturnsWithdrawnAssetsAndZeroShares() public {
        _deposit(caller, AMOUNT, caller);

        vm.prank(lendingCore);
        (uint256 assetsWithdrawn, uint256 sharesBurned) = pool.withdrawCollateral(caller, AMOUNT, 0, receiver);

        assertEq(assetsWithdrawn, AMOUNT);
        assertEq(sharesBurned, 0);
    }

    function test_WithdrawCollateral_BurnsCollateralTokenAndTransfersAssets_WhenReceiverIsCaller() public {
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        _deposit(caller, AMOUNT, caller);

        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, AMOUNT, 0, caller);

        assertEq(collateralToken.balanceOf(caller), 0);
        assertEq(collateralToken.collateralBalanceOf(caller), 0);
        assertEq(collateralToken.totalSupply(), 0);
        assertEq(asset.balanceOf(address(pool)), 0);
        assertEq(asset.balanceOf(caller), AMOUNT);
    }

    function test_WithdrawCollateral_BurnsCollateralTokenAndTransfersAssets_WhenAssetsIsOne() public {
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        _deposit(caller, MIN_AMOUNT, caller);

        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, MIN_AMOUNT, 0, receiver);

        assertEq(collateralToken.balanceOf(caller), 0);
        assertEq(collateralToken.collateralBalanceOf(caller), 0);
        assertEq(collateralToken.totalSupply(), 0);
        assertEq(asset.balanceOf(address(pool)), 0);
        assertEq(asset.balanceOf(receiver), MIN_AMOUNT);
    }

    function test_WithdrawCollateral_BurnsPartialCollateralTokenAndLeavesRemainder() public {
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        _deposit(caller, AMOUNT, caller);

        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, PARTIAL_AMOUNT, 0, receiver);

        assertEq(collateralToken.balanceOf(caller), AMOUNT - PARTIAL_AMOUNT);
        assertEq(collateralToken.collateralBalanceOf(caller), AMOUNT - PARTIAL_AMOUNT);
        assertEq(collateralToken.totalSupply(), AMOUNT - PARTIAL_AMOUNT);
        assertEq(asset.balanceOf(address(pool)), AMOUNT - PARTIAL_AMOUNT);
        assertEq(asset.balanceOf(receiver), PARTIAL_AMOUNT);
    }

    function test_WithdrawCollateral_DoesNotAffectOtherAccountsCollateral() public {
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        _deposit(caller, AMOUNT, caller);
        _deposit(other, OTHER_AMOUNT, other);

        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, AMOUNT, 0, receiver);

        assertEq(collateralToken.balanceOf(caller), 0);
        assertEq(collateralToken.balanceOf(other), OTHER_AMOUNT);
        assertEq(collateralToken.collateralBalanceOf(other), OTHER_AMOUNT);
        assertEq(collateralToken.totalSupply(), OTHER_AMOUNT);
        assertEq(asset.balanceOf(receiver), AMOUNT);
        assertEq(asset.balanceOf(address(pool)), OTHER_AMOUNT);
    }

    function test_WithdrawCollateral_Revert_WhenAssetsIsZero() public {
        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, 0, 0, receiver);
    }

    function test_WithdrawCollateral_Revert_WhenSharesIsNonZero() public {
        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, AMOUNT, 1, receiver);
    }

    function test_WithdrawCollateral_Revert_WhenAssetsIsZeroAndSharesIsNonZero() public {
        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, 0, 1, receiver);
    }

    function test_WithdrawCollateral_Revert_WhenReceiverIsZero() public {
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        _deposit(caller, AMOUNT, caller);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, AMOUNT, 0, address(0));

        assertEq(collateralToken.balanceOf(caller), AMOUNT);
        assertEq(collateralToken.collateralBalanceOf(caller), AMOUNT);
        assertEq(collateralToken.totalSupply(), AMOUNT);
        assertEq(asset.balanceOf(address(pool)), AMOUNT);
        assertEq(asset.balanceOf(caller), 0);
    }

    // seizeCollateral()

    /// @dev Protected assets are never lent out, so a seizure settles in the underlying just as a withdrawal does.
    function test_SeizeCollateral_BurnsCollateralTokenAndTransfersAssets() public {
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        _deposit(violator, AMOUNT, violator);

        vm.prank(lendingCore);
        pool.seizeCollateral(violator, PARTIAL_AMOUNT, receiver);

        assertEq(collateralToken.balanceOf(violator), AMOUNT - PARTIAL_AMOUNT);
        assertEq(collateralToken.totalSupply(), AMOUNT - PARTIAL_AMOUNT);
        assertEq(asset.balanceOf(address(pool)), AMOUNT - PARTIAL_AMOUNT);
        assertEq(asset.balanceOf(receiver), PARTIAL_AMOUNT);
    }

    /// @dev Zero shares tells the caller the seizure was settled in underlying rather than in a transferable claim.
    function test_SeizeCollateral_ReturnsSeizedAssetsAndZeroShares() public {
        _deposit(violator, AMOUNT, violator);

        vm.prank(lendingCore);
        (uint256 assetsSeized, uint256 sharesSeized) = pool.seizeCollateral(violator, PARTIAL_AMOUNT, receiver);

        assertEq(assetsSeized, PARTIAL_AMOUNT);
        assertEq(sharesSeized, 0);
    }

    function test_SeizeCollateral_Revert_WhenAssetsIsZero() public {
        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.seizeCollateral(violator, 0, receiver);
    }

    function test_SeizeCollateral_Revert_WhenAssetsExceedTheViolatorsCollateral() public {
        _deposit(violator, AMOUNT, violator);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, violator, AMOUNT, AMOUNT + 1)
        );
        vm.prank(lendingCore);
        pool.seizeCollateral(violator, AMOUNT + 1, receiver);
    }

    // borrow()

    function test_Borrow_Revert_FunctionNotAvailable() public {
        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool.borrow(caller, AMOUNT, receiver);
    }

    // repay()

    function test_Repay_Revert_FunctionNotAvailable() public {
        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool.repay(caller, AMOUNT, receiver);
    }

    function _deposit(address account, uint256 assets, address depositReceiver) internal {
        asset.mint(account, assets);
        vm.prank(account);
        asset.approve(address(pool), assets);
        vm.prank(lendingCore);
        pool.depositCollateral(account, assets, 0, depositReceiver);
    }

    function _deployCollateralisablePool(address defaultAdmin_, address hookUpdater_, address lendingCore_)
        internal
        returns (CollateralisablePool instance, ProtectedCollateralToken collateralToken_)
    {
        CollateralisablePool poolImplementation = new CollateralisablePool();
        instance = CollateralisablePool(Clones.clone(address(poolImplementation)));

        ProtectedCollateralToken collateralImplementation = new ProtectedCollateralToken();
        collateralToken_ = ProtectedCollateralToken(Clones.clone(address(collateralImplementation)));
        collateralToken_.initialize(address(instance), COLLATERAL_NAME, COLLATERAL_SYMBOL, asset.decimals());

        instance.initialize(
            defaultAdmin_,
            hookUpdater_,
            flashLoanConfigurator,
            address(0),
            0,
            0,
            lendingCore_,
            true,
            asset,
            address(collateralToken_)
        );
    }
}
