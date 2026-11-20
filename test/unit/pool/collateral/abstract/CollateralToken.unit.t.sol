// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {CollateralToken} from "src/pool/collateral/abstract/CollateralToken.sol";
import {ICollateralToken} from "src/pool/collateral/interfaces/ICollateralToken.sol";
import {CollateralTokenHarness} from "./mocks/CollateralTokenHarness.sol";

contract CollateralTokenUnitTest is Test {
    CollateralTokenHarness implementation;
    CollateralTokenHarness collateralToken;

    address pool = makeAddr("pool");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    string constant NAME = "cUSD Coin";
    string constant SYMBOL = "cUSDC";
    // Deliberately not eighteen, so a decimals getter falling back to the ERC-20 default would be visible.
    uint8 constant DECIMALS = 6;

    uint256 constant AMOUNT = 1000e18;

    function setUp() public {
        implementation = new CollateralTokenHarness();
        collateralToken = CollateralTokenHarness(Clones.clone(address(implementation)));
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

    // mint()

    function test_Mint_IncreasesBalance() public {
        vm.prank(pool);
        collateralToken.mint(alice, AMOUNT);

        assertEq(collateralToken.balanceOf(alice), AMOUNT);
    }

    function test_Mint_Revert_NotPoolCaller() public {
        vm.expectRevert(CollateralToken.NotPoolCaller.selector);
        vm.prank(alice);
        collateralToken.mint(alice, AMOUNT);
    }

    // burn()

    function test_Burn_DecreasesBalance() public {
        vm.prank(pool);
        collateralToken.mint(alice, AMOUNT);

        vm.prank(pool);
        collateralToken.burn(alice, AMOUNT);

        assertEq(collateralToken.balanceOf(alice), 0);
    }

    function test_Burn_Revert_NotPoolCaller() public {
        vm.prank(pool);
        collateralToken.mint(alice, AMOUNT);

        vm.expectRevert(CollateralToken.NotPoolCaller.selector);
        vm.prank(alice);
        collateralToken.burn(alice, AMOUNT);
    }

    // transfer()

    function test_Transfer_Revert_FunctionNotSupported() public {
        vm.expectRevert(CollateralToken.FunctionNotSupported.selector);
        vm.prank(alice);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        collateralToken.transfer(bob, AMOUNT);
    }

    // transferFrom()

    function test_TransferFrom_Revert_FunctionNotSupported() public {
        vm.expectRevert(CollateralToken.FunctionNotSupported.selector);
        vm.prank(alice);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        collateralToken.transferFrom(alice, bob, AMOUNT);
    }

    // approve()

    function test_Approve_Revert_FunctionNotSupported() public {
        vm.expectRevert(CollateralToken.FunctionNotSupported.selector);
        vm.prank(alice);
        collateralToken.approve(bob, AMOUNT);
    }

    // supportsInterface()

    function test_supportsInterface_CollateralToken_ReturnsTrue() public view {
        assertTrue(collateralToken.supportsInterface(type(ICollateralToken).interfaceId));
    }

    function test_supportsInterface_ERC20_ReturnsTrue() public view {
        assertTrue(collateralToken.supportsInterface(type(IERC20).interfaceId));
    }

    function test_supportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(collateralToken.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(collateralToken.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(collateralToken.supportsInterface(bytes4(0xffffffff)));
    }
}
