// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {CollateralToken} from "src/pool/collateral/abstract/CollateralToken.sol";
import {ProtectedCollateralToken} from "src/pool/collateral/ProtectedCollateralToken.sol";
import {BasePool} from "src/pool/abstract/BasePool.sol";
import {Collateralisable} from "src/pool/abstract/Collateralisable.sol";
import {CollateralisablePool} from "src/pool/CollateralisablePool.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract CollateralisablePoolFuzzTest is Test {
    CollateralisablePool pool;
    MockERC20 asset;

    address defaultAdmin = makeAddr("defaultAdmin");
    address hookUpdater = makeAddr("hookUpdater");
    address lendingCore = makeAddr("lendingCore");

    string constant COLLATERAL_NAME = "Protected USD Coin";
    string constant COLLATERAL_SYMBOL = "pUSDC";

    function setUp() public {
        asset = new MockERC20();
        CollateralisablePool poolImplementation = new CollateralisablePool();
        pool = CollateralisablePool(Clones.clone(address(poolImplementation)));

        ProtectedCollateralToken collateralImplementation = new ProtectedCollateralToken();
        ProtectedCollateralToken collateralToken =
            ProtectedCollateralToken(Clones.clone(address(collateralImplementation)));
        collateralToken.initialize(address(pool), COLLATERAL_NAME, COLLATERAL_SYMBOL, asset.decimals());

        pool.initialize(
            defaultAdmin, hookUpdater, address(0), address(0), 0, 0, lendingCore, false, asset, address(collateralToken)
        );
    }

    // depositCollateral()

    function testFuzz_DepositCollateral_TransfersAssetsAndMintsCollateralToken(
        address caller,
        address receiver,
        uint256 assets
    ) public {
        caller = _boundAccount(caller);
        receiver = _boundAccount(receiver);
        assets = _boundAmount(assets);
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        asset.mint(caller, assets);
        vm.prank(caller);
        asset.approve(address(pool), assets);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, assets, 0, receiver);

        assertEq(asset.balanceOf(caller), 0);
        assertEq(asset.balanceOf(address(pool)), assets);
        assertEq(collateralToken.balanceOf(receiver), assets);
        assertEq(collateralToken.collateralBalanceOf(receiver), assets);
        assertEq(asset.balanceOf(address(pool)), collateralToken.totalSupply());
    }

    function testFuzz_DepositCollateral_AccumulatesCollateralTokenBalance(
        address caller,
        address receiver,
        uint256 firstAssets,
        uint256 secondAssets
    ) public {
        caller = _boundAccount(caller);
        receiver = _boundAccount(receiver);
        firstAssets = _boundAmount(firstAssets);
        secondAssets = _boundAmount(secondAssets);
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        _deposit(caller, firstAssets, receiver);
        _deposit(caller, secondAssets, receiver);

        assertEq(asset.balanceOf(address(pool)), firstAssets + secondAssets);
        assertEq(collateralToken.balanceOf(receiver), firstAssets + secondAssets);
        assertEq(collateralToken.collateralBalanceOf(receiver), firstAssets + secondAssets);
        assertEq(asset.balanceOf(address(pool)), collateralToken.totalSupply());
    }

    function testFuzz_DepositCollateral_Revert_WhenAssetsIsZero(address caller, address receiver) public {
        caller = _boundAccount(caller);
        receiver = _boundAccount(receiver);

        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.depositCollateral(caller, 0, 0, receiver);
    }

    function testFuzz_DepositCollateral_Revert_WhenSharesIsNonZero(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) public {
        caller = _boundAccount(caller);
        receiver = _boundAccount(receiver);
        assets = _boundAmount(assets);
        shares = _boundAmount(shares);

        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.depositCollateral(caller, assets, shares, receiver);
    }

    function testFuzz_DepositCollateral_Revert_WhenAssetsIsZeroAndSharesIsNonZero(
        address caller,
        address receiver,
        uint256 shares
    ) public {
        caller = _boundAccount(caller);
        receiver = _boundAccount(receiver);
        shares = _boundAmount(shares);

        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.depositCollateral(caller, 0, shares, receiver);
    }

    // withdrawCollateral()

    function testFuzz_WithdrawCollateral_BurnsPartialCollateralTokenAndLeavesRemainder(
        address caller,
        address receiver,
        uint256 depositAssets,
        uint256 withdrawAssets
    ) public {
        caller = _boundAccount(caller);
        receiver = _boundAccount(receiver);
        depositAssets = bound(depositAssets, 2, type(uint128).max);
        withdrawAssets = bound(withdrawAssets, 1, depositAssets - 1);
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        _deposit(caller, depositAssets);

        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, withdrawAssets, 0, receiver);

        assertEq(collateralToken.balanceOf(caller), depositAssets - withdrawAssets);
        assertEq(collateralToken.collateralBalanceOf(caller), depositAssets - withdrawAssets);
        assertEq(collateralToken.totalSupply(), depositAssets - withdrawAssets);
        assertEq(asset.balanceOf(address(pool)), depositAssets - withdrawAssets);
        assertEq(asset.balanceOf(receiver), withdrawAssets);
    }

    function testFuzz_WithdrawCollateral_BurnsAllCollateralTokenAndTransfersAssets(
        address caller,
        address receiver,
        uint256 assets
    ) public {
        caller = _boundAccount(caller);
        receiver = _boundAccount(receiver);
        assets = _boundAmount(assets);
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        _deposit(caller, assets);

        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, assets, 0, receiver);

        assertEq(collateralToken.balanceOf(caller), 0);
        assertEq(collateralToken.collateralBalanceOf(caller), 0);
        assertEq(collateralToken.totalSupply(), 0);
        assertEq(asset.balanceOf(address(pool)), 0);
        assertEq(asset.balanceOf(receiver), assets);
    }

    function testFuzz_WithdrawCollateral_Revert_WhenAssetsIsZero(address caller, address receiver) public {
        caller = _boundAccount(caller);
        receiver = _boundAccount(receiver);

        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, 0, 0, receiver);
    }

    function testFuzz_WithdrawCollateral_Revert_WhenSharesIsNonZero(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) public {
        caller = _boundAccount(caller);
        receiver = _boundAccount(receiver);
        assets = _boundAmount(assets);
        shares = _boundAmount(shares);

        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, assets, shares, receiver);
    }

    function testFuzz_WithdrawCollateral_Revert_WhenAssetsIsZeroAndSharesIsNonZero(
        address caller,
        address receiver,
        uint256 shares
    ) public {
        caller = _boundAccount(caller);
        receiver = _boundAccount(receiver);
        shares = _boundAmount(shares);

        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, 0, shares, receiver);
    }

    // seizeCollateral()

    function testFuzz_SeizeCollateral_BurnsSeizedCollateralTokenAndTransfersAssets(
        address violator,
        address receiver,
        uint256 depositAssets,
        uint256 seizeAssets
    ) public {
        violator = _boundAccount(violator);
        receiver = _boundAccount(receiver);
        depositAssets = _boundAmount(depositAssets);
        seizeAssets = bound(seizeAssets, 1, depositAssets);
        CollateralToken collateralToken = CollateralToken(pool.collateralToken());
        _deposit(violator, depositAssets);

        vm.prank(lendingCore);
        pool.seizeCollateral(violator, seizeAssets, receiver);

        assertEq(collateralToken.balanceOf(violator), depositAssets - seizeAssets);
        assertEq(collateralToken.totalSupply(), depositAssets - seizeAssets);
        assertEq(asset.balanceOf(address(pool)), depositAssets - seizeAssets);
        assertEq(asset.balanceOf(receiver), seizeAssets);
    }

    function testFuzz_SeizeCollateral_Revert_WhenAssetsIsZero(address violator, address receiver) public {
        violator = _boundAccount(violator);
        receiver = _boundAccount(receiver);

        vm.expectRevert(Collateralisable.InvalidCollateralArgs.selector);
        vm.prank(lendingCore);
        pool.seizeCollateral(violator, 0, receiver);
    }

    // borrow()

    function testFuzz_Borrow_Revert_FunctionNotAvailable(address caller, uint256 amount, address receiver) public {
        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool.borrow(caller, amount, receiver);
    }

    // repay()

    function testFuzz_Repay_Revert_FunctionNotAvailable(address caller, uint256 amount, address receiver) public {
        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool.repay(caller, amount, receiver);
    }

    function _deposit(address account, uint256 assets) internal {
        _deposit(account, assets, account);
    }

    function _deposit(address account, uint256 assets, address receiver) internal {
        asset.mint(account, assets);
        vm.prank(account);
        asset.approve(address(pool), assets);
        vm.prank(lendingCore);
        pool.depositCollateral(account, assets, 0, receiver);
    }

    function _boundAccount(address account) internal returns (address) {
        uint160 account_ = uint160(account);
        if (account_ == 0 || account_ == uint160(address(pool))) account_ = uint160(makeAddr("boundedAccount"));
        return address(account_);
    }

    function _boundAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, 1, type(uint128).max);
    }
}
