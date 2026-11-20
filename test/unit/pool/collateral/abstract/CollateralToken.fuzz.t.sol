// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {CollateralTokenHarness} from "./mocks/CollateralTokenHarness.sol";

contract CollateralTokenFuzzTest is Test {
    CollateralTokenHarness collateralToken;

    address pool = makeAddr("pool");

    string constant NAME = "USD Coin";
    string constant SYMBOL = "USDC";
    uint8 constant DECIMALS = 6;

    function setUp() public {
        CollateralTokenHarness implementation = new CollateralTokenHarness();
        collateralToken = CollateralTokenHarness(Clones.clone(address(implementation)));
        collateralToken.initialize(pool, NAME, SYMBOL, DECIMALS);
    }

    // mint()

    function testFuzz_Mint_IncreasesBalanceByAmount(address account, uint256 amount) public {
        vm.assume(account != address(0));

        vm.prank(pool);
        collateralToken.mint(account, amount);

        assertEq(collateralToken.balanceOf(account), amount);
    }

    // burn()

    function testFuzz_Burn_DecreasesBalanceByAmount(address account, uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(account != address(0));
        burnAmount = bound(burnAmount, 0, mintAmount);

        vm.prank(pool);
        collateralToken.mint(account, mintAmount);

        vm.prank(pool);
        collateralToken.burn(account, burnAmount);

        assertEq(collateralToken.balanceOf(account), mintAmount - burnAmount);
    }
}
