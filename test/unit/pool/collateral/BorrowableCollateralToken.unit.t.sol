// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {BorrowableCollateralToken} from "src/pool/collateral/BorrowableCollateralToken.sol";
import {MockERC4626Pool} from "../mocks/MockERC4626Pool.sol";

contract BorrowableCollateralTokenUnitTest is Test {
    BorrowableCollateralToken collateralToken;
    MockERC4626Pool pool;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    string constant NAME = "cUSD Coin";
    string constant SYMBOL = "cUSDC";
    // Deliberately not eighteen, so a decimals getter falling back to the ERC-20 default would be visible.
    uint8 constant DECIMALS = 6;

    function setUp() public {
        pool = new MockERC4626Pool();
        BorrowableCollateralToken implementation = new BorrowableCollateralToken();
        collateralToken = BorrowableCollateralToken(Clones.clone(address(implementation)));
        collateralToken.initialize(address(pool), NAME, SYMBOL, DECIMALS);
    }

    // initialize()

    function test_Initialize_SetsNameAndSymbol() public view {
        assertEq(collateralToken.name(), "cUSD Coin");
        assertEq(collateralToken.symbol(), "cUSDC");
    }

    function test_Initialize_SetsDecimals() public view {
        assertEq(collateralToken.decimals(), DECIMALS);
    }

    function test_Initialize_SetsPool() public view {
        assertEq(address(collateralToken.pool()), address(pool));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(collateralToken.contractName(), "BorrowableCollateralToken");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(collateralToken.contractVersion(), "1.0.0");
    }

    // collateralBalanceOf()

    function test_CollateralBalanceOf_ReturnsConvertedAssetsAtOneToOneRate() public {
        uint256 shares = 1000e18;
        uint256 assets = 1000e18;
        pool.setExchangeRate(assets, shares);
        vm.prank(address(pool));
        collateralToken.mint(alice, shares);

        assertEq(collateralToken.collateralBalanceOf(alice), assets);
    }

    function test_CollateralBalanceOf_ReturnsConvertedAssetsAtNonUnitRate() public {
        uint256 shares = 1000e18;
        uint256 assets = 2000e18;
        pool.setExchangeRate(assets, shares);
        vm.prank(address(pool));
        collateralToken.mint(alice, shares);

        assertEq(collateralToken.collateralBalanceOf(alice), assets);
    }

    function test_CollateralBalanceOf_ReturnsZeroWhenNoBalance() public view {
        assertEq(collateralToken.collateralBalanceOf(alice), 0);
    }

    function test_CollateralBalanceOf_MatchesBalanceOfScaledByExchangeRate() public {
        uint256 shares = 1000e18;
        uint256 assets = 2000e18;
        pool.setExchangeRate(assets, shares);
        vm.prank(address(pool));
        collateralToken.mint(alice, shares);

        assertEq(collateralToken.collateralBalanceOf(alice), collateralToken.balanceOf(alice) * assets / shares);
    }

    // totalCollateral()

    function test_TotalCollateral_ReturnsZeroWhenThereIsNoCollateral() public view {
        assertEq(collateralToken.totalCollateral(), 0);
    }

    function test_TotalCollateral_ReturnsConvertedSupplyAtNonUnitRate() public {
        uint256 shares = 1000e18;
        uint256 assets = 2000e18;
        pool.setExchangeRate(assets, shares);
        vm.prank(address(pool));
        collateralToken.mint(alice, shares);

        assertEq(collateralToken.totalCollateral(), 2000e18);
    }

    function test_TotalCollateral_ReturnsAggregateCollateralAcrossAccounts() public {
        uint256 aliceShares = 1000e18;
        uint256 bobShares = 500e18;
        pool.setExchangeRate(3000e18, aliceShares + bobShares);
        vm.startPrank(address(pool));
        collateralToken.mint(alice, aliceShares);
        collateralToken.mint(bob, bobShares);
        vm.stopPrank();

        assertEq(collateralToken.totalCollateral(), 3000e18);
    }

    function test_TotalCollateral_ReflectsExchangeRateChanges() public {
        uint256 shares = 1000e18;
        pool.setExchangeRate(1000e18, shares);
        vm.prank(address(pool));
        collateralToken.mint(alice, shares);

        assertEq(collateralToken.totalCollateral(), 1000e18);

        pool.setExchangeRate(2500e18, shares);

        assertEq(collateralToken.totalCollateral(), 2500e18);
    }
}
