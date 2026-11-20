// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";

import {BorrowableCollateralToken} from "src/pool/collateral/BorrowableCollateralToken.sol";
import {Borrowable} from "src/pool/abstract/Borrowable.sol";
import {MockDebtToken} from "./mocks/MockDebtToken.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockOnlendFeeRegistry} from "./mocks/MockOnlendFeeRegistry.sol";
import {CollateralisableBorrowablePoolHarness} from "./mocks/CollateralisableBorrowablePoolHarness.sol";

contract CollateralisableBorrowablePoolFuzzTest is Test {
    // Covers very large token balances while keeping ERC-4626 conversions within uint256.
    uint256 internal constant MAX_ASSET_AMOUNT = 1e32;
    // Pool shares use the same decimals as the underlying; this caps aggregate seeded supply.
    uint256 internal constant MAX_SHARE_SUPPLY = 1e32;

    CollateralisableBorrowablePoolHarness internal pool;
    MockERC20 internal asset;
    MockDebtToken internal debtToken;

    address internal defaultAdmin = makeAddr("defaultAdmin");
    address internal hookUpdater = makeAddr("hookUpdater");
    address internal operatorFeeConfigurator = makeAddr("operatorFeeConfigurator");
    address internal lendingCore = makeAddr("lendingCore");
    address internal borrower = makeAddr("borrower");
    address internal caller = makeAddr("caller");
    address internal receiver = makeAddr("receiver");
    address internal owner = makeAddr("owner");
    address internal other = makeAddr("other");

    function setUp() public {
        asset = new MockERC20();
        CollateralisableBorrowablePoolHarness poolImplementation = new CollateralisableBorrowablePoolHarness();
        pool = CollateralisableBorrowablePoolHarness(Clones.clone(address(poolImplementation)));

        BorrowableCollateralToken collateralImplementation = new BorrowableCollateralToken();
        BorrowableCollateralToken collateralToken =
            BorrowableCollateralToken(Clones.clone(address(collateralImplementation)));
        collateralToken.initialize(address(pool), "USD Coin", "USDC", asset.decimals());

        debtToken = new MockDebtToken(address(pool), asset.decimals());
        MockOnlendFeeRegistry feeRegistry = new MockOnlendFeeRegistry(makeAddr("onlendFeeRecipient"));
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
            address(collateralToken),
            address(debtToken),
            address(feeRegistry),
            makeAddr("operatorFeeRecipient")
        );
    }

    // depositCollateral()

    function testFuzz_depositCollateral_RevertsWhenPositiveAssetsWouldMintZeroShares(uint256 debt) public {
        debt = bound(debt, 2, MAX_ASSET_AMOUNT);
        pool.seedShares(other, 1);
        debtToken.seedDebt(borrower, debt);

        vm.expectRevert(Borrowable.ZeroAmount.selector);
        vm.prank(lendingCore);
        pool.depositCollateral(caller, 1, 0, receiver);
    }

    // seizeCollateral()

    /// @dev The seizure hands the escrowed shares over instead of redeeming them, so it moves no underlying.
    function testFuzz_seizeCollateral_MovesSharesAndNoUnderlyingAtAnyUtilisation(
        uint256 collateralShares,
        uint256 idleLiquidity,
        uint256 assets
    ) public {
        collateralShares = bound(collateralShares, 1, MAX_SHARE_SUPPLY);
        idleLiquidity = bound(idleLiquidity, 0, Math.min(collateralShares, MAX_ASSET_AMOUNT));
        pool.seedCollateralPosition(caller, collateralShares);
        _seedIdleLiquidity(idleLiquidity);
        debtToken.seedDebt(borrower, collateralShares - idleLiquidity);
        assets = bound(assets, 1, collateralShares);

        vm.prank(lendingCore);
        pool.seizeCollateral(caller, assets, receiver);

        assertEq(pool.balanceOf(receiver), assets);
        assertEq(asset.balanceOf(receiver), 0);
        assertEq(asset.balanceOf(address(pool)), idleLiquidity);
        assertEq(pool.idleLiquidity(), idleLiquidity);
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
