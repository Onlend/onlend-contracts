// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {ProtectedCollateralToken} from "src/pool/collateral/ProtectedCollateralToken.sol";

contract ProtectedCollateralTokenUnitTest is Test {
    ProtectedCollateralToken collateralToken;

    address pool = makeAddr("pool");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    string constant NAME = "cUSD Coin";
    string constant SYMBOL = "cUSDC";
    // Deliberately not eighteen, so a decimals getter falling back to the ERC-20 default would be visible.
    uint8 constant DECIMALS = 6;

    function setUp() public {
        ProtectedCollateralToken implementation = new ProtectedCollateralToken();
        collateralToken = ProtectedCollateralToken(Clones.clone(address(implementation)));
        collateralToken.initialize(pool, NAME, SYMBOL, DECIMALS);
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
        assertEq(collateralToken.pool(), pool);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(collateralToken.contractName(), "ProtectedCollateralToken");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(collateralToken.contractVersion(), "1.0.0");
    }

    // collateralBalanceOf()

    function test_CollateralBalanceOf_ReturnsBalance() public {
        uint256 assets = 1000e18;
        vm.prank(pool);
        collateralToken.mint(alice, assets);

        assertEq(collateralToken.collateralBalanceOf(alice), assets);
    }

    function test_CollateralBalanceOf_ReturnsZeroWhenNoBalance() public view {
        assertEq(collateralToken.collateralBalanceOf(alice), 0);
    }

    function test_CollateralBalanceOf_MatchesBalanceOf() public {
        uint256 assets = 1000e18;
        vm.prank(pool);
        collateralToken.mint(alice, assets);

        assertEq(collateralToken.collateralBalanceOf(alice), collateralToken.balanceOf(alice));
    }

    // totalCollateral()

    function test_TotalCollateral_ReturnsZeroWhenThereIsNoCollateral() public view {
        assertEq(collateralToken.totalCollateral(), 0);
    }

    function test_TotalCollateral_ReturnsAggregateCollateralAcrossAccounts() public {
        uint256 aliceAssets = 1000e18;
        uint256 bobAssets = 500e18;
        vm.startPrank(pool);
        collateralToken.mint(alice, aliceAssets);
        collateralToken.mint(bob, bobAssets);
        vm.stopPrank();

        assertEq(collateralToken.totalCollateral(), aliceAssets + bobAssets);
    }
}
